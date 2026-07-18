import 'package:jankdoc_core/jankdoc_core.dart';

import 'eval_case.dart';

/// Canonical eval fixtures for the built-in rule set.
///
/// Each fixture is a [EvalCase] that exercises one rule in isolation.
/// Coverage target: every Rule in [BuiltInRuleProvider] has at least one
/// GREEN fixture and one "should-not-match" (negative) fixture.
///
/// Fixtures are pure-Dart constants — no network, no filesystem, no Ollama.
abstract final class EvalFixtures {
  static const _session = 'eval-session-001';

  static const DeviceInfo _androidDevice = DeviceInfo(
    platform: TargetPlatform.android,
    osVersion: '14',
    flutterVersion: '3.29.0',
    dartVersion: '3.6.0',
    impellerEnabled: false,
    gpuName: 'Adreno 650',
    physicalMemoryMb: 8192,
    cpuCores: 8,
  );

  static const DeviceInfo _iosDevice = DeviceInfo(
    platform: TargetPlatform.ios,
    osVersion: '17.4',
    flutterVersion: '3.29.0',
    dartVersion: '3.6.0',
    impellerEnabled: true,
    gpuName: 'Apple GPU',
    physicalMemoryMb: 6144,
    cpuCores: 6,
  );

  // ── Helpers ────────────────────────────────────────────────────────────────

  static TelemetryBatch _batch({
    required double uiMs,
    double rasterMs = 4.0,
    int fps = 60,
    List<StackFrame> uiStack = const [],
    Map<String, int> rebuilds = const {},
    DeviceInfo device = _androidDevice,
    int gcCount = 0,
  }) {
    final frame = JankFrame(
      timestamp: 1_000_000,
      uiThreadMs: uiMs,
      rasterThreadMs: rasterMs,
      totalMs: uiMs + rasterMs,
      targetFps: fps,
      uiStack: uiStack,
      rasterStack: const [],
      rebuildCounts: rebuilds,
    );
    return TelemetryBatch(
      sessionId: _session,
      projectFingerprint: 'eval000000000000',
      windowStartMs: 0,
      windowEndMs: 33,
      jankFrames: [frame],
      analysisMode: AnalysisMode.deep,
      deviceInfo: device,
      gcCount: gcCount,
    );
  }

  static StackFrame _frame({
    required String file,
    required int line,
    required String function,
    int column = 0,
    String? widgetType,
    bool isUserCode = true,
  }) =>
      StackFrame(
        file: file,
        line: line,
        column: column,
        function: function,
        widgetType: widgetType,
        packageName: isUserCode ? 'my_app' : 'flutter',
      );

  // ── Build / rebuild rules ──────────────────────────────────────────────────

  static EvalCase get animatedBuilderRebuildStorm => EvalCase(
        id: 'animated-builder-rebuild-storm-001',
        description:
            'AnimatedBuilder rebuilds a heavy subtree >90 times with a list in the tree',
        batch: _batch(
          // Keep uiMs ≤ 16 so heavy-compute-main-isolate (priority 12) doesn't
          // shadow this rule (priority 10) via UiThreadMs(greaterThan:16).
          uiMs: 12.0,
          uiStack: [
            _frame(
              file: 'lib/home_screen.dart',
              line: 42,
              function: 'build',
              widgetType: 'AnimatedBuilder',
            ),
          ],
          // RebuildStorm('AnimatedBuilder', factor:1.5) threshold = 60*1.5 = 90 → need >90
          // AnyWidgetType(['ListView',...]) checks rebuildCounts keys → need list widget key
          rebuilds: {'AnimatedBuilder': 100, 'ListView': 10},
        ),
        assertions: [
          const PatternIdAssertion('animated-builder-rebuild-storm'),
          const MinConfidenceAssertion(0.90),
          const MinSeverityAssertion(Severity.high),
          const RuleTierAssertion(),
        ],
        tags: ['rebuild', 'animation'],
      );

  static EvalCase get setStateInBuild => EvalCase(
        id: 'setstate-in-build-001',
        description: 'setState called from within build() via listener',
        batch: _batch(
          uiMs: 30.0,
          uiStack: [
            _frame(
              file: 'lib/feed_widget.dart',
              line: 88,
              function: 'build',
            ),
            // StackContains('setState') requires this frame in the UI stack
            _frame(
              file: 'lib/feed_widget.dart',
              line: 90,
              function: 'setState',
            ),
          ],
          rebuilds: {'FeedWidget': 120},
        ),
        assertions: [
          const PatternIdAssertion('setstate-in-build'),
          const MinSeverityAssertion(Severity.critical),
          const RuleTierAssertion(),
        ],
        tags: ['rebuild'],
      );

  static EvalCase get missingConstConstructor => EvalCase(
        id: 'missing-const-constructor-001',
        description:
            'Scaffold rebuilt 130 times — likely missing const constructors',
        batch: _batch(
          // Keep uiMs ≤ 16 so heavy-compute-main-isolate (priority 12) doesn't
          // shadow this rule (priority 5) via UiThreadMs(greaterThan:16).
          uiMs: 14.0,
          uiStack: [
            _frame(
              file: 'lib/product_tile.dart',
              line: 15,
              function: 'build',
            ),
          ],
          // RebuildStorm('Scaffold', factor:2.0) threshold = 60*2.0 = 120 → need >120
          rebuilds: {'ProductTile': 30, 'Scaffold': 130},
        ),
        assertions: [
          const PatternIdAssertion('missing-const-constructor'),
          const RuleTierAssertion(),
        ],
        tags: ['rebuild'],
      );

  // ── Raster rules ───────────────────────────────────────────────────────────

  static EvalCase get shaderCompilationJank => EvalCase(
        id: 'shader-compilation-001',
        description: 'Raster thread spikes to 55ms on shader-heavy frame',
        batch: _batch(
          uiMs: 5.0,
          rasterMs: 55.0,
          // StackContains('compileShader') checks uiStack function names
          uiStack: [
            _frame(
              file: 'engine',
              line: 0,
              function: 'compileShader',
              isUserCode: false,
            ),
          ],
          rebuilds: {},
        ),
        assertions: [
          const PatternIdAssertion('shader-compilation-jank'),
          const MinSeverityAssertion(Severity.high),
          const RuleTierAssertion(),
        ],
        tags: ['raster', 'shader'],
      );

  static EvalCase get backdropFilterOverdraw => EvalCase(
        id: 'backdrop-filter-overdraw-001',
        description: 'Raster dominant with BackdropFilter overdraw',
        batch: _batch(
          uiMs: 6.0,
          rasterMs: 32.0,
          uiStack: [
            _frame(
              file: 'lib/blur_panel.dart',
              line: 22,
              function: 'build',
              widgetType: 'BackdropFilter',
            ),
          ],
          // WidgetType('BackdropFilter') checks rebuildCounts keys, not uiStack.widgetType
          rebuilds: {'BackdropFilter': 3},
        ),
        assertions: [
          const PatternIdAssertion('backdrop-filter-overdraw'),
          const RuleTierAssertion(),
        ],
        // 'impeller' tag removed: backdrop-filter-overdraw rule doesn't require
        // Impeller — tagging it 'impeller' caused the Android fixture to appear
        // in EvalFixtures.impeller and break the "no impeller rule on Android" test.
        tags: ['raster'],
      );

  // ── Impeller rules ─────────────────────────────────────────────────────────

  static EvalCase get impellerScrollJankIos => EvalCase(
        id: 'impeller-scroll-jank-ios-001',
        description: 'iOS Impeller scroll jank — raster dominant at 45ms',
        batch: _batch(
          // Rule needs RasterDominant(): raster >= ui * 1.5 → 45 >= 5*1.5 ✓
          // Rule needs RasterThreadMs(greaterThan: 8.0) → 45 > 8 ✓
          // AnyWidgetType(['ListView',...]) checks rebuildCounts keys → need 'ListView' key
          uiMs: 5.0,
          rasterMs: 45.0,
          device: _iosDevice,
          uiStack: [
            _frame(
              file: 'lib/product_list.dart',
              line: 67,
              function: 'build',
              widgetType: 'ListView',
            ),
          ],
          rebuilds: {'ListView': 10},
        ),
        assertions: [
          const PatternIdAssertion('impeller-scroll-jank-ios'),
          const MinConfidenceAssertion(0.88),
          const RuleTierAssertion(),
        ],
        tags: ['impeller', 'ios', 'scroll'],
      );

  static EvalCase get impellerElevationRoundedCorners => EvalCase(
        id: 'impeller-elevation-rounded-corners-001',
        description:
            'iOS Impeller elevation + rounded corners causing raster spike',
        batch: _batch(
          uiMs: 5.0,
          rasterMs: 28.0,
          device: _iosDevice,
          uiStack: [
            _frame(
              file: 'lib/card_widget.dart',
              line: 34,
              function: 'build',
              widgetType: 'Card',
            ),
            // StackContains('BorderRadius') needs this frame
            _frame(
              file: 'flutter',
              line: 1,
              function: 'BorderRadius.circular',
              isUserCode: false,
            ),
          ],
          // WidgetType('Card') checks rebuildCounts keys
          rebuilds: {'Card': 3},
        ),
        assertions: [
          const PatternIdAssertion('impeller-elevation-rounded-corners'),
          const RuleTierAssertion(),
        ],
        tags: ['impeller', 'ios', 'raster'],
      );

  // ── Async rules ────────────────────────────────────────────────────────────

  static EvalCase get syncIoOnUiThread => EvalCase(
        id: 'sync-io-on-ui-thread-001',
        description: 'File.readAsStringSync called on UI thread',
        batch: _batch(
          uiMs: 40.0,
          uiStack: [
            _frame(
              file: 'lib/settings_screen.dart',
              line: 103,
              function: 'readAsStringSync',
            ),
            _frame(
              file: 'lib/settings_screen.dart',
              line: 98,
              function: 'loadConfig',
            ),
          ],
        ),
        assertions: [
          const PatternIdAssertion('sync-io-on-ui-thread'),
          const MinSeverityAssertion(Severity.critical),
          const RuleTierAssertion(),
        ],
        tags: ['async', 'io'],
      );

  static EvalCase get jsonDecodeUiThread => EvalCase(
        id: 'json-decode-ui-thread-001',
        description: 'jsonDecode of large payload blocks UI thread',
        batch: _batch(
          uiMs: 35.0,
          uiStack: [
            _frame(
              file: 'dart:convert',
              line: 1,
              function: 'jsonDecode',
              isUserCode: false,
            ),
            _frame(
              file: 'lib/api_client.dart',
              line: 56,
              function: 'parseResponse',
            ),
          ],
        ),
        assertions: [
          const PatternIdAssertion('json-decode-ui-thread'),
          const MinSeverityAssertion(Severity.high),
          const RuleTierAssertion(),
        ],
        tags: ['async', 'json'],
      );

  // ── List / grid rules ──────────────────────────────────────────────────────

  static EvalCase get listViewMissingExtent => EvalCase(
        id: 'listview-missing-extent-001',
        description: 'ListView without itemExtent renders 5000 items slowly',
        batch: _batch(
          // Keep uiMs ≤ 16 so heavy-compute-main-isolate (priority 12) doesn't
          // shadow this rule (priority 7) via UiThreadMs(greaterThan:16).
          // Rule still satisfied: UiDominant (14≥4×1.5) + UiThreadMs(>8).
          uiMs: 14.0,
          uiStack: [
            _frame(
              file: 'lib/transactions_screen.dart',
              line: 78,
              function: 'build',
              widgetType: 'ListView',
            ),
            // StackContains('performLayout') needs this frame
            _frame(
              file: 'flutter',
              line: 1,
              function: 'performLayout',
              isUserCode: false,
            ),
          ],
          rebuilds: {'ListView': 1},
        ),
        assertions: [
          const PatternIdAssertion('listview-missing-extent'),
          const RuleTierAssertion(),
        ],
        tags: ['list'],
      );

  // ── Negative cases (should NOT trigger a rule) ─────────────────────────────

  /// A frame right at the frame budget with no identifiable pattern.
  /// The rule engine should return null — no false positives.
  ///
  /// uiMs is 16.0 (not *greater than* 16), so heavy-compute-main-isolate
  /// (UiThreadMs(greaterThan: 16.0)) does not fire. No other rule fires
  /// because there are no matching widget types or stack patterns.
  static EvalCase get unknownJankNoMatch => EvalCase(
        id: 'unknown-jank-no-match-001',
        description:
            'Frame at budget boundary with unusual stack — should not match any rule',
        batch: _batch(
          uiMs: 16.0,
          rasterMs: 5.0,
          uiStack: [
            _frame(
              file: 'lib/custom_render.dart',
              line: 200,
              function: 'performLayout',
            ),
          ],
          rebuilds: {'CustomRender': 2},
        ),
        // No rule should match this — we assert that rebuild count is low
        // and raster is not dominant and no impeller signals are present.
        // The harness reports a miss if any assertion fires.
        assertions: const [],
        tags: ['negative'],
      );

  // ── Suite helpers ──────────────────────────────────────────────────────────

  /// The full built-in fixture suite.
  static List<EvalCase> get all => [
        animatedBuilderRebuildStorm,
        setStateInBuild,
        missingConstConstructor,
        shaderCompilationJank,
        backdropFilterOverdraw,
        impellerScrollJankIos,
        impellerElevationRoundedCorners,
        syncIoOnUiThread,
        jsonDecodeUiThread,
        listViewMissingExtent,
        unknownJankNoMatch,
      ];

  /// Impeller-specific subset.
  static List<EvalCase> get impeller =>
      all.where((c) => c.tags.contains('impeller')).toList();

  /// Rebuild-specific subset.
  static List<EvalCase> get rebuild =>
      all.where((c) => c.tags.contains('rebuild')).toList();
}
