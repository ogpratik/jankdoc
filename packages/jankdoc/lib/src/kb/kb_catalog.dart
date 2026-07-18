import 'package:jankdoc_core/jankdoc_core.dart';

/// The built-in KB catalog.
///
/// These entries are embedded by [KbSeeder] at daemon startup and loaded into
/// the [VectorStore] for RAG retrieval. Each entry maps 1:1 to a rule patternId.
///
/// Once the `jankdoc-kb` repo ships KB Bundles, this catalog is replaced by
/// loading entries from the bundle's [EmbeddingManifest] — no Ollama call
/// needed at startup. Until then, seeding calls Ollama at runtime.
List<KbEntry> get kbCatalog => _kbCatalog;

final List<KbEntry> _kbCatalog = [
  // ── Build / Rebuild ────────────────────────────────────────────────────────

  KbEntry(
    id: 'animated-builder-rebuild-storm',
    category: KbCategory.rebuild,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'AnimatedBuilder Rebuild Storm',
    description: '''
AnimatedBuilder placed too high in the widget tree causes its entire subtree to rebuild on every animation tick (typically 60–120 times per second). When the AnimatedBuilder wraps a complex list item or large widget tree, the rebuild cost compounds — every child is laid out, painted, and composited on each frame even if only a tiny visual element is actually animated.

Diagnosis signals: rebuild count for AnimatedBuilder exceeds targetFps × 1.5 (≥ 90 rebuilds/s at 60 fps); a list widget (ListView, GridView, SliverList) is also rebuilding. UI thread time spikes without a corresponding raster spike.

Fix: Move AnimatedBuilder to wrap only the animated child widget. Extract the static parts of the list item into a StatelessWidget or use the `child` parameter of AnimatedBuilder (which is built once and passed into the builder callback, skipping unnecessary rebuilds).''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      widgetTypes: ['AnimatedBuilder', 'ListView', 'GridView'],
      embedChunks: [
        'AnimatedBuilder placed too high in the widget tree causes its entire subtree to rebuild on every animation tick. Move AnimatedBuilder to wrap only the animated child widget.',
      ],
    ),
    sources: [
      'https://docs.flutter.dev/perf/best-practices',
      'https://api.flutter.dev/flutter/widgets/AnimatedBuilder-class.html',
    ],
    fixGuidance:
        'Move AnimatedBuilder to wrap only the animated child; use the child parameter for static subtrees.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 25,
      maxReductionPercent: 75,
      description: '4–12ms frame time reduction on 60fps devices.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'setstate-in-build',
    category: KbCategory.rebuild,
    channel: KbChannel.stable,
    severity: Severity.critical,
    title: 'setState Called During Build',
    description: '''
Calling setState() inside a build() method (or a callback that fires during build) creates a rebuild loop: build → setState → scheduleFrame → build again. Flutter detects many of these cases and throws assertions in debug mode, but indirect calls through listeners, InheritedWidgets, or SchedulerBinding callbacks can slip through.

Diagnosis signals: setState appears in the UI thread CPU stack trace during a jank frame; rebuild count for the widget is extremely high (often >100/frame); UI thread time is dominant (uiMs >> rasterMs).

Fix: Never call setState during the synchronous build phase. Move listener registration to initState/didChangeDependencies. Use addPostFrameCallback to schedule updates after the current frame.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      stackPatterns: ['setState', 'build'],
      embedChunks: [
        'Calling setState inside build() creates a rebuild loop. Move listener registration to initState and use addPostFrameCallback for post-build updates.',
      ],
    ),
    sources: [
      'https://docs.flutter.dev/testing/common-errors#setstate-called-during-build',
      'https://api.flutter.dev/flutter/widgets/State/setState.html',
    ],
    fixGuidance:
        'Move setState calls out of build(); register listeners in initState() and unregister in dispose().',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 50,
      maxReductionPercent: 95,
      description:
          'Eliminates the rebuild loop — often resolves the jank entirely.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'missing-const-constructor',
    category: KbCategory.rebuild,
    channel: KbChannel.stable,
    severity: Severity.medium,
    title: 'Missing const Constructor — Unnecessary Rebuilds',
    description: '''
When a widget class lacks a const constructor, Flutter cannot cache the widget instance across builds. The parent's setState() forces the entire subtree to be rebuilt even when nothing changed. At scale (large lists, deep trees) this creates measurable UI thread jank.

Diagnosis signals: Scaffold or other structural widgets rebuild at very high rates (rebuild count > targetFps × 2, i.e. >120/s at 60 fps); UI thread is dominant; there are no async or I/O signals in the stack.

Fix: Add `const` constructors to stateless leaf widgets. Use `const` at call sites wherever the arguments are compile-time constants. Enable the `prefer_const_constructors` lint.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      widgetTypes: ['Scaffold'],
      embedChunks: [
        'Missing const constructor causes unnecessary widget rebuilds. Add const constructors to stateless widgets and use const at call sites.',
      ],
    ),
    sources: [
      'https://dart.dev/effective-dart/usage#prefer-const-over-new',
      'https://docs.flutter.dev/perf/best-practices#use-const-widgets',
    ],
    fixGuidance:
        'Add const constructors to StatelessWidgets and use const at all constant call sites.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 20,
      maxReductionPercent: 60,
      description: 'Reduces rebuild frequency proportional to const adoption.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'expensive-computation-in-build',
    category: KbCategory.mainThreadJank,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'Expensive Computation in build()',
    description: '''
Performing CPU-intensive work (sorting, filtering, encoding, cryptography) synchronously inside build() blocks the UI thread. Flutter's frame budget is 16.6ms at 60 fps — any computation that takes longer causes dropped frames.

Diagnosis signals: UI thread dominant (uiMs >> rasterMs × 2); stack contains jsonDecode, jsonEncode, compute, sort, or heavy algorithm functions; no Isolate usage.

Fix: Move expensive work to a separate Isolate using `compute()` (for one-shot tasks) or `Isolate.run()` (Dart 2.19+). Cache results with memoization.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      stackPatterns: ['jsonDecode', 'jsonEncode', 'sort'],
      embedChunks: [
        'Expensive CPU computation in build() blocks the UI thread. Use compute() or Isolate.run() to offload work and cache results to avoid recomputation.',
      ],
    ),
    sources: [
      'https://docs.flutter.dev/perf/best-practices',
      'https://api.flutter.dev/flutter/foundation/compute.html',
    ],
    fixGuidance:
        'Cache computation results outside build(); use compute() or Isolate.run() for heavy work.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 30,
      maxReductionPercent: 80,
      description:
          'Depends on computation cost; isolate offload typically eliminates the jank entirely.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'inherited-widget-over-rebuild',
    category: KbCategory.rebuild,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'InheritedWidget Triggering Excessive Rebuilds',
    description: '''
InheritedWidget notifies every descendant that calls `context.dependOnInheritedWidgetOfExactType()` whenever it changes. If the InheritedWidget holds a large state object that changes frequently, or if widgets depend on the entire object rather than a specific field, many unnecessary rebuilds occur.

Diagnosis signals: didChangeDependencies or dependOnInheritedWidgetOfExactType in the CPU stack; rebuild count for Consumer widgets exceeds targetFps × 2; UI thread dominant.

Fix: Split large InheritedWidgets into smaller, focused ones. Use `select()` with Riverpod or Provider to subscribe to only the fields that affect a given widget. Override `updateShouldNotify` to return false when the relevant data hasn't changed.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      stackPatterns: [
        'didChangeDependencies',
        'dependOnInheritedWidgetOfExactType'
      ],
      widgetTypes: ['Consumer'],
      embedChunks: [
        'InheritedWidget triggering excessive rebuilds. Split into smaller InheritedWidgets, use select() to subscribe to specific fields, override updateShouldNotify.',
      ],
    ),
    sources: [
      'https://api.flutter.dev/flutter/widgets/InheritedWidget-class.html',
      'https://docs.flutter.dev/data-and-backend/state-mgmt/options',
    ],
    fixGuidance:
        'Split large InheritedWidgets by concern; use Riverpod select() or override updateShouldNotify.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 30,
      maxReductionPercent: 70,
      description:
          'Reduces rebuild scope to only widgets that depend on changed fields.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'helper-method-instead-of-widget',
    category: KbCategory.rebuild,
    channel: KbChannel.stable,
    severity: Severity.medium,
    title: 'Helper Method Instead of Widget (No Rebuild Caching)',
    description: '''
Extracting UI into a private method (e.g. `_buildHeader()`) instead of a separate StatelessWidget means Flutter treats it as part of the parent's build output with no identity. The parent's setState() unconditionally rebuilds the helper's output even if its inputs haven't changed, and `const` cannot be used.

Diagnosis signals: Column or Row widgets rebuilding at high rates (>targetFps × 3); UI dominant; no async signals; many nested helper method calls in the stack.

Fix: Extract helper methods into proper StatelessWidget subclasses with const constructors. Flutter's element reconciliation can then skip rebuilding them when their props are unchanged.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      widgetTypes: ['Column', 'Row'],
      embedChunks: [
        'Helper method _buildX() instead of StatelessWidget prevents Flutter rebuild caching. Extract into StatelessWidget with const constructor.',
      ],
    ),
    sources: [
      'https://docs.flutter.dev/perf/best-practices#control-build-cost',
      'https://www.youtube.com/watch?v=IOyq-eTRhvo',
    ],
    fixGuidance:
        'Replace _buildX() helper methods with StatelessWidget subclasses that have const constructors.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 20,
      maxReductionPercent: 50,
      description:
          'Flutter can skip rebuilding extracted widgets when inputs are unchanged.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'value-notifier-whole-tree-rebuild',
    category: KbCategory.rebuild,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'ValueNotifier / ChangeNotifier Rebuilding Whole Tree',
    description: '''
Attaching a ValueListenableBuilder or ListenableBuilder high in the widget tree (e.g. on MaterialApp or a top-level Scaffold) causes the entire subtree to rebuild every time the notifier fires. This is functionally correct but performance-catastrophic for complex UIs.

Diagnosis signals: notifyListeners or ValueListenableBuilder in the CPU stack; rebuild count for MaterialApp or high-level widgets exceeds targetFps × 1.0; UI thread dominant.

Fix: Move the ValueListenableBuilder as close as possible to the widget that actually uses the value. Consider splitting the notifier into smaller, focused notifiers.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      stackPatterns: ['notifyListeners', 'ValueListenableBuilder'],
      widgetTypes: ['MaterialApp'],
      embedChunks: [
        'ValueNotifier or ChangeNotifier attached too high in the tree rebuilds the entire subtree. Move ValueListenableBuilder close to the consuming widget.',
      ],
    ),
    sources: [
      'https://api.flutter.dev/flutter/foundation/ValueListenableBuilder-class.html',
      'https://docs.flutter.dev/perf/best-practices',
    ],
    fixGuidance:
        'Move ValueListenableBuilder as close to the consuming widget as possible; split large notifiers.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 30,
      maxReductionPercent: 70,
      description:
          'Limits rebuild scope to just the widget that consumes the value.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  // ── Raster ──────────────────────────────────────────────────────────────────

  KbEntry(
    id: 'raster-overdraw-opacity',
    category: KbCategory.overdraw,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'Opacity Widget Causing saveLayer GPU Overdraw',
    description: '''
The Opacity widget forces the GPU to composite its subtree into an offscreen buffer (via saveLayer) before blending it with the scene. This is expensive — it allocates a full-resolution texture and requires two GPU passes. On large widgets or in lists, this can easily push the raster thread over the 16ms frame budget.

Diagnosis signals: raster thread dominant (rasterMs ≥ uiMs × 1.5); raster time > 8ms; Opacity widget in rebuild counts or saveLayer in the CPU stack.

Fix: Replace Opacity with FadeTransition (for animated opacity) or AnimatedOpacity (for setState-driven transitions). These use RenderObject-level compositing which is much cheaper.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      widgetTypes: ['Opacity'],
      stackPatterns: ['saveLayer'],
      minRasterThreadMs: 8.0,
      embedChunks: [
        'Opacity widget triggers saveLayer GPU overdraw. Replace with FadeTransition for animations or AnimatedOpacity for setState-driven transitions.',
      ],
    ),
    sources: [
      'https://docs.flutter.dev/perf/rendering-performance#opacity-and-clipping',
      'https://api.flutter.dev/flutter/widgets/FadeTransition-class.html',
    ],
    fixGuidance:
        'Replace Opacity with FadeTransition (animated) or AnimatedOpacity (setState-driven).',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 20,
      maxReductionPercent: 50,
      description:
          '3–8ms raster time reduction by eliminating the offscreen buffer.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'raster-overdraw-clip',
    category: KbCategory.overdraw,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'ClipRRect / ClipPath Causing Raster Overdraw',
    description: '''
ClipRRect, ClipPath, and ClipOval with non-trivial clip shapes force the GPU to use saveLayer to isolate the clipped subtree. The cost grows with the area of the clipped widget and the number of layers beneath it.

Diagnosis signals: raster thread dominant; rasterMs > 8ms; ClipRRect, ClipPath, or ClipOval in rebuild counts.

Fix: Prefer Container with borderRadius and a BoxDecoration instead of ClipRRect for rounded corners. If ClipPath is required, mark the widget with a RepaintBoundary.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      widgetTypes: ['ClipRRect', 'ClipPath', 'ClipOval'],
      minRasterThreadMs: 8.0,
      embedChunks: [
        'ClipRRect/ClipPath forces saveLayer and raster overdraw. Use Container with BorderRadius instead for rounded corners.',
      ],
    ),
    sources: [
      'https://docs.flutter.dev/perf/rendering-performance',
      'https://api.flutter.dev/flutter/widgets/ClipRRect-class.html',
    ],
    fixGuidance:
        'Replace ClipRRect with Container + BoxDecoration borderRadius; wrap unavoidable ClipPath in RepaintBoundary.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 20,
      maxReductionPercent: 45,
      description:
          'Eliminates the saveLayer allocation for rounded corner cases.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'shader-compilation-jank',
    category: KbCategory.shaderCompilation,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'Shader Compilation Jank (First-Frame Hitches)',
    description: '''
Flutter compiles GLSL shaders on first use. When a new visual effect (gradient, blur, shadow, custom paint) is encountered for the first time, the GPU driver compiles the shader synchronously on the raster thread, causing a frame hitch of 50–500ms.

Diagnosis signals: raster dominant (rasterMs ≥ uiMs × 2); rasterMs > 16ms; compileShader appears in the raster/UI stack; hitch occurs on first navigation or first use of a visual effect.

Fix: Use SkSL shader warm-up (Skia backend) or migrate to Impeller which eliminates runtime shader compilation.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      stackPatterns: ['compileShader'],
      minRasterThreadMs: 16.0,
      embedChunks: [
        'Shader compilation jank on first frame. Use SkSL warm-up with --cache-sksl or migrate to Impeller for offline shader compilation.',
      ],
    ),
    sources: [
      'https://docs.flutter.dev/perf/shader',
      'https://docs.flutter.dev/perf/impeller',
    ],
    fixGuidance:
        'Capture shaders with --cache-sksl and bundle them, or enable Impeller to eliminate runtime compilation.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 60,
      maxReductionPercent: 100,
      description:
          'Eliminates the one-time shader compilation hitch on first render.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'backdrop-filter-overdraw',
    category: KbCategory.overdraw,
    channel: KbChannel.stable,
    severity: Severity.medium,
    title: 'BackdropFilter / ImageFilter.blur GPU Overdraw',
    description: '''
BackdropFilter blurs everything behind it — Flutter must composite the entire scene behind the filter into an offscreen buffer, apply the Gaussian blur kernel, then composite the result back. The cost scales with the blur radius and the covered area. Multiple BackdropFilters stack multiplicatively.

Diagnosis signals: raster thread dominant (rasterMs ≥ uiMs × 1.5); BackdropFilter in widget rebuild counts or ImageFilter.blur in the CPU stack.

Fix: Minimise the blur area. Cache the blurred background as a static image if it doesn't change. Limit sigmaX/sigmaY values. Use RepaintBoundary to isolate the blurred layer.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      widgetTypes: ['BackdropFilter'],
      stackPatterns: ['ImageFilter.blur'],
      embedChunks: [
        'BackdropFilter blurs the entire scene behind it causing GPU overdraw. Minimise blur area, reduce sigma values, use RepaintBoundary.',
      ],
    ),
    sources: [
      'https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html',
      'https://docs.flutter.dev/perf/rendering-performance',
    ],
    fixGuidance:
        'Reduce blur area and sigma values; wrap BackdropFilter in RepaintBoundary to isolate the blurred layer.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 15,
      maxReductionPercent: 40,
      description: 'Depends on blur radius and covered area.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'missing-repaint-boundary',
    category: KbCategory.overdraw,
    channel: KbChannel.stable,
    severity: Severity.medium,
    title: 'Missing RepaintBoundary on Animated Widget',
    description: '''
Without a RepaintBoundary, an animated widget that repaints every frame causes its entire parent layer to repaint too — including sibling widgets that haven't changed. For complex UIs with background content, this is a significant raster-thread waste.

Diagnosis signals: raster thread dominant; rasterMs > 8ms; AnimatedBuilder, AnimatedContainer, or TweenAnimationBuilder in rebuild counts but no RepaintBoundary.

Fix: Wrap independently animated widgets in RepaintBoundary. Flutter creates a new layer for the bounded widget, limiting repaints to just that layer on animation ticks.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      widgetTypes: [
        'AnimatedBuilder',
        'AnimatedContainer',
        'TweenAnimationBuilder'
      ],
      minRasterThreadMs: 8.0,
      embedChunks: [
        'Missing RepaintBoundary on animated widget causes sibling repaints. Wrap independently animated widgets in RepaintBoundary.',
      ],
    ),
    sources: [
      'https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html',
      'https://docs.flutter.dev/perf/rendering-performance#repaint-rainbow',
    ],
    fixGuidance:
        'Wrap independently animated widgets in RepaintBoundary to isolate their raster layer.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 15,
      maxReductionPercent: 35,
      description:
          'Limits raster work to just the animated layer on each tick.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  // ── Async / Concurrency ───────────────────────────────────────────────────

  KbEntry(
    id: 'sync-io-on-ui-thread',
    category: KbCategory.mainThreadJank,
    channel: KbChannel.stable,
    severity: Severity.critical,
    title: 'Synchronous I/O Blocking the UI Thread',
    description: '''
Dart's synchronous I/O methods (File.readAsStringSync, File.writeAsStringSync, Directory.listSync, etc.) block the calling thread until the OS completes the operation. When called on the UI thread, they freeze the app for the entire I/O duration.

Diagnosis signals: readAsStringSync, writeAsStringSync, existsSync, or listSync in the UI thread CPU stack; uiMs dominates and is ≥ rasterMs × 2; UI thread time > 16ms.

Fix: Always use async I/O on the UI thread. For operations that must be synchronous, use Isolate.run() or compute() to run them off the main isolate.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      stackPatterns: [
        'readAsStringSync',
        'writeAsStringSync',
        'existsSync',
        'listSync'
      ],
      embedChunks: [
        'Synchronous I/O (readAsStringSync etc.) blocking the UI thread. Use async I/O or Isolate.run() for file operations.',
      ],
    ),
    sources: [
      'https://api.dart.dev/stable/dart-io/File-class.html',
      'https://docs.flutter.dev/perf/best-practices#avoid-expensive-synchronous-work-in-build',
    ],
    fixGuidance:
        'Replace *Sync I/O methods with async equivalents; use Isolate.run() for unavoidably synchronous operations.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 50,
      maxReductionPercent: 100,
      description:
          'Eliminates the UI thread block entirely; UI stays responsive during I/O.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'json-decode-ui-thread',
    category: KbCategory.mainThreadJank,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'JSON Decoding Blocking the UI Thread',
    description: '''
json.decode() is a synchronous, CPU-bound operation that parses the entire JSON string in one go. For API responses larger than ~50 KB, this takes more than the 16ms frame budget and causes a visible stutter.

Diagnosis signals: jsonDecode, json.decode, or convert.json in the UI CPU stack; uiMs > 8ms and UI dominant; no Isolate usage visible in the stack.

Fix: Move JSON decoding off the main isolate using `compute(jsonDecode, jsonString)` or `Isolate.run()`.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      stackPatterns: ['jsonDecode', 'json.decode', 'convert.json'],
      embedChunks: [
        'JSON decoding blocking the UI thread for large payloads. Use compute(jsonDecode, ...) or Isolate.run() to decode off the main isolate.',
      ],
    ),
    sources: [
      'https://docs.flutter.dev/cookbook/networking/background-parsing',
      'https://api.flutter.dev/flutter/foundation/compute.html',
    ],
    fixGuidance:
        'Use compute(jsonDecode, jsonString) or Isolate.run() to decode large JSON payloads off the main isolate.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 40,
      maxReductionPercent: 100,
      description:
          'Eliminates the decode stutter; 8–20ms improvement for 50–500KB payloads.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'heavy-compute-main-isolate',
    category: KbCategory.mainThreadJank,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'Heavy Computation on the Main Isolate',
    description: '''
Dart is single-threaded per isolate. Any synchronous CPU-intensive operation (sorting large lists, image processing, cryptography, regex on large strings) runs on the main isolate's event loop and blocks all UI updates.

Diagnosis signals: UI thread dominant (uiMs ≥ rasterMs × 2) and uiMs > 16ms; no Isolate or compute() visible in the stack; the operation is not I/O.

Fix: Offload to a worker isolate using `compute()` for one-shot tasks or `Isolate.spawn()` for long-running workers.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      embedChunks: [
        'Heavy CPU computation on main isolate blocking UI updates. Use compute() for one-shot tasks or Isolate.spawn() for long-running workers.',
      ],
    ),
    sources: [
      'https://dart.dev/guides/language/concurrency',
      'https://api.flutter.dev/flutter/foundation/compute.html',
    ],
    fixGuidance:
        'Offload heavy computation with compute() or Isolate.run(); never block the main isolate > 16ms.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 40,
      maxReductionPercent: 95,
      description:
          'Moves the CPU work off the UI thread; UI stays responsive at 60fps.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'platform-channel-ui-block',
    category: KbCategory.platformChannel,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'Platform Channel Call Blocking UI Thread',
    description: '''
MethodChannel.invokeMethod() is asynchronous but if the native side performs synchronous work that takes too long, or if the call is awaited inside build(), the UI can appear frozen.

Diagnosis signals: MethodChannel, BasicMessageChannel, or EventChannel in the UI thread CPU stack; uiMs > 8ms and UI dominant; the call site is inside a build() method.

Fix: Never call platform channels from build(). Pre-fetch results in initState() and display with FutureBuilder.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      stackPatterns: ['MethodChannel', 'BasicMessageChannel', 'EventChannel'],
      embedChunks: [
        'Platform channel call inside build() or blocking UI thread. Pre-fetch results in initState() and use FutureBuilder for display.',
      ],
    ),
    sources: [
      'https://docs.flutter.dev/platform-integration/platform-channels',
      'https://docs.flutter.dev/perf/isolates',
    ],
    fixGuidance:
        'Move platform channel calls out of build(); pre-fetch in initState() and present via FutureBuilder.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 25,
      maxReductionPercent: 60,
      description:
          'Eliminates the synchronous channel round-trip from the frame budget.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  // ── Impeller ──────────────────────────────────────────────────────────────

  KbEntry(
    id: 'impeller-scroll-jank-ios',
    category: KbCategory.impeller,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'Impeller Scroll Jank on iOS (flutter/flutter#137992)',
    description: '''
A known Impeller regression on iOS causes scroll jank when lists contain widgets with complex paint operations (gradients, shadows, custom painters). The raster thread spikes because Impeller's tile-based rendering path handles certain draw calls less efficiently than Skia in specific scenarios.

Diagnosis signals: iOS device with Impeller enabled; raster thread dominant (rasterMs ≥ uiMs × 1.5) and rasterMs > 8ms; ListView, GridView, CustomScrollView, PageView, or SingleChildScrollView in the widget tree.

Fix: Add RepaintBoundary around complex list items. Simplify per-item paint operations — replace gradients with flat colors where possible.''',
    flutterVersionRange: '>=3.10.0',
    detectionSignals: const DetectionSignals(
      widgetTypes: ['ListView', 'GridView', 'CustomScrollView', 'PageView'],
      requiresImpeller: true,
      minRasterThreadMs: 8.0,
      embedChunks: [
        'Impeller scroll jank on iOS (flutter/flutter#137992). Add RepaintBoundary around complex list items, simplify paint operations.',
      ],
    ),
    sources: [
      'https://github.com/flutter/flutter/issues/137992',
      'https://docs.flutter.dev/perf/impeller',
    ],
    fixGuidance:
        'Wrap complex list items in RepaintBoundary; simplify gradients and shadows in list item builds.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 20,
      maxReductionPercent: 50,
      description:
          'RepaintBoundary isolates per-item paint; improvement varies by list item complexity.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'impeller-powervr-rogue-spike',
    category: KbCategory.impeller,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'Impeller PowerVR Rogue GPU Spike (flutter/flutter#161304)',
    description: '''
Devices with PowerVR Rogue series GPUs (common in older MediaTek and some Imagination Technologies chipsets) show severe raster spikes with Impeller on Android. The GPU driver's interaction with Impeller's Vulkan command buffers triggers unusually long GPU synchronisation stalls.

Diagnosis signals: Android device with Impeller enabled; GPU name contains "PowerVR Rogue"; raster thread ≥ UI thread × 2.

Fix: Disable Impeller for affected devices in AndroidManifest.xml.''',
    flutterVersionRange: '>=3.16.0',
    detectionSignals: const DetectionSignals(
      requiresImpeller: true,
      embedChunks: [
        'Impeller PowerVR Rogue GPU spike on Android (flutter/flutter#161304). Disable Impeller for affected devices via AndroidManifest.',
      ],
    ),
    sources: [
      'https://github.com/flutter/flutter/issues/161304',
      'https://docs.flutter.dev/release/breaking-changes/android-impeller-preview',
    ],
    fixGuidance:
        'Disable Impeller for PowerVR Rogue devices via AndroidManifest.xml meta-data.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 50,
      maxReductionPercent: 90,
      description:
          'Switching to Skia on affected devices eliminates the GPU stalls.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'impeller-elevation-rounded-corners',
    category: KbCategory.impeller,
    channel: KbChannel.stable,
    severity: Severity.medium,
    title:
        'Impeller Elevation + Rounded Corners Raster Spike (flutter/flutter#162312)',
    description: '''
On iOS with Impeller, combining Material elevation (shadows) with BorderRadius triggers expensive path tessellation on the raster thread. The Card widget with its default elevation is the most common trigger.

Diagnosis signals: iOS device with Impeller enabled; raster thread dominant (rasterMs ≥ uiMs × 1.5); Card, Material, or PhysicalModel in rebuild counts; BorderRadius in the CPU stack.

Fix: Remove or reduce elevation on Cards inside scrollable lists. Use a flat card design (elevation: 0) with border decoration instead.''',
    flutterVersionRange: '>=3.10.0',
    detectionSignals: const DetectionSignals(
      widgetTypes: ['Card', 'Material', 'PhysicalModel'],
      stackPatterns: ['elevation', 'BorderRadius'],
      requiresImpeller: true,
      embedChunks: [
        'Impeller elevation + rounded corners raster spike on iOS (flutter/flutter#162312). Use flat card design with border decoration instead of elevation.',
      ],
    ),
    sources: [
      'https://github.com/flutter/flutter/issues/162312',
      'https://docs.flutter.dev/perf/impeller',
    ],
    fixGuidance:
        'Replace elevation on scrollable Cards with a flat design using border decoration; wrap in RepaintBoundary.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 20,
      maxReductionPercent: 50,
      description:
          'Eliminating tessellated shadows reduces raster-thread work per scroll frame.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'impeller-custom-scroll-view-android',
    category: KbCategory.impeller,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'Impeller CustomScrollView Android Jank (flutter/flutter#168788)',
    description: '''
CustomScrollView with complex slivers shows increased raster-thread jank on Android with Impeller enabled compared to Skia. The issue is related to how Impeller handles the clipping and compositing of sliver children during fast fling gestures.

Diagnosis signals: Android device with Impeller enabled; CustomScrollView in rebuild counts; raster thread dominant during scroll.

Fix: Try disabling Impeller for the affected Android versions or simplify sliver content. Track flutter/flutter#168788 for upstream resolution.''',
    flutterVersionRange: '>=3.16.0',
    detectionSignals: const DetectionSignals(
      widgetTypes: ['CustomScrollView'],
      requiresImpeller: true,
      embedChunks: [
        'Impeller CustomScrollView Android jank (flutter/flutter#168788). Simplify sliver content or disable Impeller on affected Android versions.',
      ],
    ),
    sources: ['https://github.com/flutter/flutter/issues/168788'],
    fixGuidance:
        'Prefer SliverList over complex custom slivers; consider disabling Impeller on affected Android versions.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 15,
      maxReductionPercent: 40,
      description:
          'Simplifying sliver content reduces per-frame compositing cost.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'impeller-general-regression',
    category: KbCategory.impeller,
    channel: KbChannel.stable,
    severity: Severity.medium,
    title: 'General Impeller Performance Regression (flutter/flutter#169423)',
    description: '''
A broad class of scenes renders slower under Impeller than under Skia due to differences in rendering architecture. Impeller uses a tile-based deferred renderer which is faster for most workloads but slower for certain overdraw-heavy scenes or scenes with many small draw calls.

Diagnosis signals: Impeller enabled; raster thread dominant; rasterMs > 16ms; no more specific Impeller pattern matches.

Fix: Profile with GPU frame profiler to identify the expensive draw calls. Reduce overdraw. Consider per-widget RepaintBoundaries.''',
    flutterVersionRange: '>=3.10.0',
    detectionSignals: const DetectionSignals(
      requiresImpeller: true,
      minRasterThreadMs: 16.0,
      embedChunks: [
        'General Impeller performance regression vs Skia (flutter/flutter#169423). Profile GPU draw calls, reduce overdraw, add RepaintBoundaries.',
      ],
    ),
    sources: [
      'https://github.com/flutter/flutter/issues/169423',
      'https://docs.flutter.dev/perf/ui-performance',
    ],
    fixGuidance:
        'Use Flutter Overdraw inspector to reduce overdraw; add RepaintBoundaries around independently rendering subtrees.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 10,
      maxReductionPercent: 35,
      description:
          'Varies widely — depends on the specific draw calls triggering the regression.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  // ── List / Grid ────────────────────────────────────────────────────────────

  KbEntry(
    id: 'listview-missing-extent',
    category: KbCategory.listGrid,
    channel: KbChannel.stable,
    severity: Severity.medium,
    title: 'ListView Without itemExtent — Slow Layout',
    description: '''
Without itemExtent or prototypeItem, ListView must lay out each item to determine its height before it can calculate the scroll extent and decide which items are visible. For long lists this means O(n) layout work.

Diagnosis signals: UI thread dominant; ListView in rebuild counts; performLayout in the CPU stack; uiMs > 8ms.

Fix: Set itemExtent if all items have the same fixed height. Use prototypeItem if items have the same type. For truly variable heights, use SliverList with a more efficient delegate.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      widgetTypes: ['ListView'],
      stackPatterns: ['performLayout'],
      embedChunks: [
        'ListView without itemExtent causes O(n) layout for off-screen items. Set itemExtent for uniform-height lists or use prototypeItem.',
      ],
    ),
    sources: [
      'https://api.flutter.dev/flutter/widgets/ListView/itemExtent.html',
      'https://docs.flutter.dev/perf/best-practices#use-itemextent-in-listviews',
    ],
    fixGuidance:
        'Set itemExtent for fixed-height lists; use prototypeItem for same-type variable-height lists.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 20,
      maxReductionPercent: 60,
      description:
          'O(1) layout math vs O(n) item measurement; improvement scales with list length.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'listview-non-lazy',
    category: KbCategory.listGrid,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'Non-Lazy ListView (All Children Built at Once)',
    description: '''
ListView(children: [...]) builds ALL child widgets immediately, even those far outside the viewport. For lists of more than ~20 items this is wasteful; for long lists it is a major jank source.

Diagnosis signals: UI thread dominant; ListView in rebuild counts; SliverList in the CPU stack; rebuild count for ListView exceeds targetFps × 0.5.

Fix: Replace ListView(children: [...]) with ListView.builder() which builds children lazily on demand.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      widgetTypes: ['ListView'],
      stackPatterns: ['SliverList'],
      embedChunks: [
        'Non-lazy ListView(children:[...]) builds all items at once. Replace with ListView.builder() for lazy item construction.',
      ],
    ),
    sources: [
      'https://api.flutter.dev/flutter/widgets/ListView-class.html',
      'https://docs.flutter.dev/cookbook/lists/long-lists',
    ],
    fixGuidance:
        'Replace ListView(children:[...]) with ListView.builder() for O(1) viewport-based rendering.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 40,
      maxReductionPercent: 90,
      description:
          'Reduces item construction from O(n) to O(visible items) — typically ~20 items.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'list-missing-keys',
    category: KbCategory.listGrid,
    channel: KbChannel.stable,
    severity: Severity.medium,
    title: 'Dynamic List Missing Widget Keys',
    description: '''
When a dynamic list reorders or removes items without keys, Flutter's reconciliation algorithm cannot match old widget instances to new ones. It falls back to rebuilding and remounting every widget in the affected range.

Diagnosis signals: UI thread dominant; ListView or GridView in rebuild counts; updateChild in the CPU stack; ListTile or item widget rebuild count exceeds targetFps × 2.

Fix: Provide ValueKey(item.id) to every item in a dynamic list.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      widgetTypes: ['ListView', 'GridView', 'ListTile'],
      stackPatterns: ['updateChild'],
      embedChunks: [
        'Dynamic list missing widget keys causes full rebuild on reorder. Add ValueKey(item.id) to list items.',
      ],
    ),
    sources: [
      'https://api.flutter.dev/flutter/foundation/Key-class.html',
      'https://www.youtube.com/watch?v=kn0EOS-ZiIc',
    ],
    fixGuidance:
        'Add ValueKey(item.id) to every item in dynamic lists to enable Flutter reconciliation.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 20,
      maxReductionPercent: 55,
      description:
          'Flutter skips rebuilding unchanged items; improvement scales with list size.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'image-in-list-no-cache',
    category: KbCategory.imageLoading,
    channel: KbChannel.stable,
    severity: Severity.high,
    title: 'Network Images in List Without Caching',
    description: '''
Image.network() fetches and decodes images every time the widget is first built. In a ListView, items are recycled as you scroll — if images aren't cached, the same URLs are fetched repeatedly.

Diagnosis signals: UI or raster dominant; ListView or GridView in rebuilds; Image.network or NetworkImage in the CPU stack.

Fix: Use cached_network_image or flutter_cache_manager. Specify cacheWidth/cacheHeight to decode at display resolution.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      widgetTypes: ['ListView', 'GridView'],
      stackPatterns: ['Image.network', 'NetworkImage'],
      embedChunks: [
        'Network images in list without caching causes redundant fetches on scroll. Use CachedNetworkImage with memCacheWidth/Height.',
      ],
    ),
    sources: [
      'https://pub.dev/packages/cached_network_image',
      'https://docs.flutter.dev/cookbook/images/cached-images',
    ],
    fixGuidance:
        'Replace Image.network with CachedNetworkImage; set memCacheWidth/Height to display resolution.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 30,
      maxReductionPercent: 70,
      description:
          'Eliminates network round-trips for cached images; decode cost also reduced.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),

  KbEntry(
    id: 'image-no-resize-cache',
    category: KbCategory.imageLoading,
    channel: KbChannel.stable,
    severity: Severity.medium,
    title: 'Images Decoded at Full Resolution (Missing cacheWidth/cacheHeight)',
    description: '''
Flutter decodes network and asset images at their native resolution by default. A 4K image displayed at 100×100 logical pixels still allocates a 4K texture in GPU memory. The raster thread bears the decode cost.

Diagnosis signals: raster thread dominant; instantiateImageCodec or decodeImageFromList in the CPU stack.

Fix: Specify cacheWidth and/or cacheHeight on Image widgets to instruct Flutter to resize during decode.''',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      stackPatterns: ['instantiateImageCodec', 'decodeImageFromList'],
      embedChunks: [
        'Images decoded at full native resolution waste GPU memory. Set cacheWidth/cacheHeight to display resolution (logical size × devicePixelRatio).',
      ],
    ),
    sources: [
      'https://api.flutter.dev/flutter/widgets/Image/cacheWidth.html',
      'https://docs.flutter.dev/perf/best-practices#rendering-and-layout',
    ],
    fixGuidance:
        'Set cacheWidth/cacheHeight on Image to logical_size × devicePixelRatio to decode at display resolution.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 20,
      maxReductionPercent: 60,
      description:
          'Up to 16× memory reduction for 4K-to-thumbnail decode; raster time scales proportionally.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  ),
];
