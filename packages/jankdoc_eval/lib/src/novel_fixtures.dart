import 'package:jankdoc_core/jankdoc_core.dart';

import 'eval_case.dart';

/// Five "novel" jank scenarios that do NOT match any built-in rule.
///
/// These are the cases that force the LLM tier to work. Each fixture is
/// hand-crafted so `RuleEngine.evaluate()` returns null against it — verified
/// by `test/novel_fixtures_test.dart`.
///
/// The expected pattern IDs use lowercase-kebab convention and MAY be new IDs
/// that don't exist as rules — they represent the *knowledge base entries* the
/// LLM should retrieve and cite, not necessarily a matching rule.
///
/// Every case's assertions include:
///   - Expected pattern ID (must match top LLM diagnosis)
///   - `HasSourcesAssertion` (the LLM must cite at least one KB source URL)
///   - Minimum confidence 0.55 (LLM tier baseline; rule tier is higher)
abstract final class NovelFixtures {
  static const _session = 'llm-novel-session-001';
  static const _fingerprint = 'llm000000000000';

  static const DeviceInfo _pixel8 = DeviceInfo(
    platform: TargetPlatform.android,
    osVersion: '14',
    flutterVersion: '3.29.0',
    dartVersion: '3.6.0',
    impellerEnabled: false,
    gpuName: 'Mali-G715 MC10',
    physicalMemoryMb: 8192,
    cpuCores: 9,
  );

  static const DeviceInfo _iphone15Pro = DeviceInfo(
    platform: TargetPlatform.ios,
    osVersion: '17.5',
    flutterVersion: '3.29.0',
    dartVersion: '3.6.0',
    impellerEnabled: true,
    gpuName: 'Apple A17 Pro',
    physicalMemoryMb: 8192,
    cpuCores: 6,
  );

  /// All 5 novel cases in stable order.
  static List<EvalCase> get all => [
        largeSyncListDecoding,
        rebuildStormViaProvider,
        offscreenTextureBinding,
        canvasSaveLayerInPaint,
        obscureFramebufferOverdrawIos,
      ];

  // ── 1. Large synchronous list decoding via a custom parser ─────────────────
  //
  // Rule pre-filter has `json-decode-ui-thread` (StackContains 'jsonDecode')
  // but this case uses `CustomListParser.parseAll` — the LLM should recognise
  // the pattern via the >100k iterations + UI thread dominance.
  //
  // uiMs kept ≤ 16 so heavy-compute-main-isolate (UiThreadMs > 16.0) does not
  // fire.
  static EvalCase get largeSyncListDecoding => EvalCase(
        id: 'novel-large-sync-list-decoding-001',
        description: 'Synchronous parsing of a 50k-row CSV on the UI thread. '
            'Not caught by json-decode rule because parser is custom.',
        batch: _batch(
          uiMs: 15.5,
          uiStack: [
            _frame(
              file: 'lib/analytics/csv_ingest.dart',
              line: 142,
              function: 'CustomListParser.parseAll',
            ),
            _frame(
              file: 'lib/analytics/csv_ingest.dart',
              line: 89,
              function: 'AnalyticsScreen._loadData',
            ),
            _frame(
              file: 'lib/screens/analytics_screen.dart',
              line: 34,
              function: 'AnalyticsScreen.build',
            ),
          ],
        ),
        assertions: const [
          // Nearest KB vocabulary match — the LLM can only ground answers in
          // pattern IDs the KB actually defines (all 26 listed in kb_catalog.dart).
          PatternIdAssertion('heavy-compute-main-isolate'),
          MinConfidenceAssertion(0.55),
          HasSourcesAssertion(),
        ],
      );

  // ── 2. Provider rebuild storm without ValueNotifier or notifyListeners ─────
  //
  // Existing `value-notifier-whole-tree-rebuild` requires notifyListeners in
  // the stack. This case uses a provider package's own listener without
  // touching the built-in ValueNotifier hierarchy.
  //
  // Keep the ratio below UiDominant + RebuildStorm thresholds for
  // MaterialApp so no rebuild-storm rule fires.
  static EvalCase get rebuildStormViaProvider => EvalCase(
        id: 'novel-provider-rebuild-storm-001',
        description:
            'Root Provider<Model> rebuilds MaterialApp every state change '
            '— rebuild storm through custom Provider ecosystem.',
        batch: _batch(
          uiMs: 12,
          rasterMs: 5,
          rebuilds: const {'HomeScreen': 40, 'ProviderScope': 40},
          uiStack: [
            _frame(
              file: 'lib/state/session_provider.dart',
              line: 71,
              function: 'SessionProvider._pushUpdate',
            ),
            _frame(
              file: 'lib/state/session_provider.dart',
              line: 23,
              function: 'SessionProvider.setActive',
            ),
          ],
        ),
        assertions: const [
          PatternIdAssertion('value-notifier-whole-tree-rebuild'),
          MinConfidenceAssertion(0.55),
          HasSourcesAssertion(),
        ],
      );

  // ── 3. Offscreen texture binding jank on Android ───────────────────────────
  //
  // Neither impeller rules nor missing-repaint-boundary catches this — it's a
  // platform texture (video) that keeps re-binding to the GLES context.
  //
  // Keep rasterMs ≤ 8 so raster-overdraw-* and missing-repaint-boundary
  // (RasterThreadMs > 8) don't fire.
  static EvalCase get offscreenTextureBinding => EvalCase(
        id: 'novel-offscreen-texture-binding-001',
        description:
            'Off-screen Texture widget keeps binding to the GLES context '
            '— raster-heavy but not overdraw/opacity.',
        batch: _batch(
          uiMs: 4,
          rasterMs: 7.5,
          uiStack: [
            _frame(
              file: 'lib/media/video_preview.dart',
              line: 55,
              function: 'VideoPreview.build',
              widgetType: 'Texture',
            ),
          ],
        ),
        assertions: const [
          PatternIdAssertion('missing-repaint-boundary'),
          MinConfidenceAssertion(0.55),
          HasSourcesAssertion(),
        ],
      );

  // ── 4. saveLayer inside a CustomPainter's paint() ─────────────────────────
  //
  // `raster-overdraw-opacity` requires Opacity widget or saveLayer *in the
  // stack*. This case has saveLayer indirectly via `Canvas.saveLayer` inside
  // a CustomPainter — the LLM must recognise the CustomPainter class name.
  //
  // Raster kept below 8 ms so raster-overdraw-* rules don't trigger.
  static EvalCase get canvasSaveLayerInPaint => EvalCase(
        id: 'novel-canvas-savelayer-in-paint-001',
        description:
            'CustomPainter calls Canvas.saveLayer per frame — expensive '
            'raster-layer work not caught by widget-typed rules.',
        batch: _batch(
          uiMs: 6,
          rasterMs: 7.5,
          uiStack: [
            _frame(
              file: 'lib/widgets/glow_painter.dart',
              line: 42,
              function: 'GlowPainter.paint',
            ),
            _frame(
              file: 'lib/widgets/glow_painter.dart',
              line: 61,
              function: 'GlowPainter._paintHalo',
            ),
          ],
        ),
        assertions: const [
          PatternIdAssertion('raster-overdraw-opacity'),
          MinConfidenceAssertion(0.55),
          HasSourcesAssertion(),
        ],
      );

  // ── 5. iOS/Impeller framebuffer overdraw not covered by existing rules ────
  //
  // `impeller-scroll-jank-ios` triggers on scroll views; this case is a
  // stationary composited layer stack. Novel pattern for the LLM to catch.
  //
  // Raster kept below 8 ms so raster-overdraw-* rules don't trigger.
  static EvalCase get obscureFramebufferOverdrawIos => EvalCase(
        id: 'novel-impeller-deep-repaint-boundary-001',
        description:
            'Deep RepaintBoundary chain (>8 layers) on iOS+Impeller causes '
            'framebuffer overdraw — not a scroll rule, not saveLayer.',
        batch: _batch(
          uiMs: 5,
          rasterMs: 7.5,
          uiStack: [
            _frame(
              file: 'lib/games/hud/status_overlay.dart',
              line: 78,
              function: 'StatusOverlay.build',
              widgetType: 'RepaintBoundary',
            ),
            _frame(
              file: 'lib/games/hud/status_overlay.dart',
              line: 91,
              function: 'StatusOverlay._buildLayers',
              widgetType: 'RepaintBoundary',
            ),
          ],
          device: _iphone15Pro,
        ),
        assertions: const [
          PatternIdAssertion('impeller-general-regression'),
          MinConfidenceAssertion(0.55),
          HasSourcesAssertion(),
        ],
      );

  // ── Helpers ───────────────────────────────────────────────────────────────

  static TelemetryBatch _batch({
    required double uiMs,
    double rasterMs = 4.0,
    List<StackFrame> uiStack = const [],
    Map<String, int> rebuilds = const {},
    DeviceInfo device = _pixel8,
  }) {
    final frame = JankFrame(
      timestamp: 1_000_000,
      uiThreadMs: uiMs,
      rasterThreadMs: rasterMs,
      totalMs: uiMs + rasterMs,
      targetFps: 60,
      uiStack: uiStack,
      rasterStack: const [],
      rebuildCounts: rebuilds,
    );
    return TelemetryBatch(
      sessionId: _session,
      projectFingerprint: _fingerprint,
      windowStartMs: 0,
      windowEndMs: 33,
      jankFrames: [frame],
      analysisMode: AnalysisMode.deep,
      deviceInfo: device,
    );
  }

  static StackFrame _frame({
    required String file,
    required int line,
    required String function,
    String? widgetType,
  }) =>
      StackFrame(
        file: file,
        line: line,
        column: 0,
        function: function,
        widgetType: widgetType,
        packageName: 'my_app',
      );
}
