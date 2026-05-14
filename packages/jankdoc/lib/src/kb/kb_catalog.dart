import 'kb_entry.dart';

/// The built-in Knowledge Base catalog.
///
/// Contains one [KbEntry] per rule patternId. Entries are embedded by
/// [KbSeeder] at daemon startup and loaded into the [VectorStore] for RAG.
///
/// Content guidelines:
///   • First paragraph: what the problem is and why it causes jank.
///   • Second paragraph: how to diagnose it (stack signals, rebuild counts).
///   • Third paragraph: the fix — concrete API names, code patterns.
///   • Keep entries ≤ 400 tokens so they fit comfortably in the LLM context.
const List<KbEntry> kbCatalog = [
  // ── Build / Rebuild ────────────────────────────────────────────────────────

  KbEntry(
    id: 'animated-builder-rebuild-storm',
    title: 'AnimatedBuilder Rebuild Storm',
    tags: ['rebuild', 'animation', 'performance'],
    content: '''
AnimatedBuilder placed too high in the widget tree causes its entire subtree to rebuild on every animation tick (typically 60–120 times per second). When the AnimatedBuilder wraps a complex list item or large widget tree, the rebuild cost compounds — every child is laid out, painted, and composited on each frame even if only a tiny visual element is actually animated.

Diagnosis signals: rebuild count for AnimatedBuilder exceeds targetFps × 1.5 (≥ 90 rebuilds/s at 60 fps); a list widget (ListView, GridView, SliverList) is also rebuilding. UI thread time spikes without a corresponding raster spike.

Fix: Move AnimatedBuilder to wrap only the animated child widget. Extract the static parts of the list item into a StatelessWidget or use the `child` parameter of AnimatedBuilder (which is built once and passed into the builder callback, skipping unnecessary rebuilds).

```dart
// ❌ Wraps too high — rebuilds entire list item on every tick
AnimatedBuilder(
  animation: _controller,
  builder: (context, child) => ListTile(
    title: Text(item.title),        // rebuilt 60×/s for no reason
    trailing: RotatedBox(quarterTurns: _turns, child: Icon(Icons.refresh)),
  ),
)

// ✅ Only the animated part rebuilds
ListTile(
  title: Text(item.title),          // rebuilt only when item changes
  trailing: AnimatedBuilder(
    animation: _controller,
    builder: (context, _) =>
        RotatedBox(quarterTurns: _turns, child: Icon(Icons.refresh)),
  ),
)
```
''',
    sources: [
      'https://docs.flutter.dev/perf/best-practices',
      'https://api.flutter.dev/flutter/widgets/AnimatedBuilder-class.html',
      'https://www.youtube.com/watch?v=3-4ddVPFIGc',
    ],
  ),

  KbEntry(
    id: 'setstate-in-build',
    title: 'setState Called During Build',
    tags: ['rebuild', 'setState', 'critical'],
    content: '''
Calling setState() inside a build() method (or a callback that fires during build) creates a rebuild loop: build → setState → scheduleFrame → build again. Flutter detects many of these cases and throws assertions in debug mode, but indirect calls through listeners, InheritedWidgets, or SchedulerBinding callbacks can slip through.

Diagnosis signals: setState appears in the UI thread CPU stack trace during a jank frame; rebuild count for the widget is extremely high (often >100/frame); UI thread time is dominant (uiMs >> rasterMs).

Fix: Never call setState during the synchronous build phase. Move listener registration to initState/didChangeDependencies. If you need to respond to a dependency change, use addPostFrameCallback or schedule the update after the current frame:

```dart
// ❌ Triggers loop — setState inside build
@override
Widget build(BuildContext context) {
  myNotifier.addListener(() => setState(() {}));  // registered on every build!
  return ...;
}

// ✅ Register once in initState
@override
void initState() {
  super.initState();
  myNotifier.addListener(_onChanged);
}

void _onChanged() => setState(() {});

@override
void dispose() {
  myNotifier.removeListener(_onChanged);
  super.dispose();
}
```
''',
    sources: [
      'https://docs.flutter.dev/testing/common-errors#setstate-called-during-build',
      'https://api.flutter.dev/flutter/widgets/State/setState.html',
    ],
  ),

  KbEntry(
    id: 'missing-const-constructor',
    title: 'Missing const Constructor — Unnecessary Rebuilds',
    tags: ['rebuild', 'const', 'performance'],
    content: '''
When a widget class lacks a const constructor, Flutter cannot cache the widget instance across builds. The parent's setState() forces the entire subtree to be rebuilt even when nothing changed. At scale (large lists, deep trees) this creates measurable UI thread jank.

Diagnosis signals: Scaffold or other structural widgets rebuild at very high rates (rebuild count > targetFps × 2, i.e. >120/s at 60 fps); UI thread is dominant; there are no async or I/O signals in the stack.

Fix: Add `const` constructors to stateless leaf widgets. Use `const` at call sites wherever the arguments are compile-time constants. Enable the `prefer_const_constructors` lint.

```dart
// ❌ Rebuilds on every parent setState
class MyIcon extends StatelessWidget {
  MyIcon({super.key, required this.color});  // no const
  final Color color;
  @override Widget build(BuildContext context) => Icon(Icons.star, color: color);
}

// ✅ Cached by Flutter's element tree
class MyIcon extends StatelessWidget {
  const MyIcon({super.key, required this.color});  // const!
  final Color color;
  @override Widget build(BuildContext context) => Icon(Icons.star, color: color);
}

// At call site:
const MyIcon(color: Colors.amber)  // zero allocation on rebuild
```
''',
    sources: [
      'https://dart.dev/effective-dart/usage#prefer-const-over-new',
      'https://docs.flutter.dev/perf/best-practices#use-const-widgets',
    ],
  ),

  KbEntry(
    id: 'expensive-computation-in-build',
    title: 'Expensive Computation in build()',
    tags: ['rebuild', 'compute', 'isolate'],
    content: '''
Performing CPU-intensive work (sorting, filtering, encoding, cryptography) synchronously inside build() blocks the UI thread. Flutter's frame budget is 16.6ms at 60 fps — any computation that takes longer causes dropped frames.

Diagnosis signals: UI thread dominant (uiMs >> rasterMs × 2); stack contains jsonDecode, jsonEncode, compute, sort, or heavy algorithm functions; no Isolate usage.

Fix: Move expensive work to a separate Isolate using `compute()` (for one-shot tasks) or `Isolate.run()` (Dart 2.19+). Cache results with memoization. Use flutter_hooks or Riverpod's `FutureProvider` to avoid recomputing on every build.

```dart
// ❌ Blocks UI thread on every build
@override
Widget build(BuildContext context) {
  final sorted = items.sortedBy((i) => i.score);  // O(n log n) every frame
  return ListView.builder(...);
}

// ✅ Compute once, cache result
late final Future<List<Item>> _sorted =
    compute(_sortItems, items);  // runs in separate isolate

@override
Widget build(BuildContext context) {
  return FutureBuilder(
    future: _sorted,
    builder: (_, snap) => snap.hasData
        ? ListView.builder(...)
        : const CircularProgressIndicator(),
  );
}
```
''',
    sources: [
      'https://docs.flutter.dev/perf/best-practices',
      'https://api.flutter.dev/flutter/foundation/compute.html',
    ],
  ),

  KbEntry(
    id: 'inherited-widget-over-rebuild',
    title: 'InheritedWidget Triggering Excessive Rebuilds',
    tags: ['rebuild', 'inherited-widget', 'state'],
    content: '''
InheritedWidget notifies every descendant that calls `context.dependOnInheritedWidgetOfExactType()` whenever it changes. If the InheritedWidget holds a large state object that changes frequently, or if widgets depend on the entire object rather than a specific field, many unnecessary rebuilds occur.

Diagnosis signals: didChangeDependencies or dependOnInheritedWidgetOfExactType in the CPU stack; rebuild count for Consumer widgets exceeds targetFps × 2; UI thread dominant.

Fix: Split large InheritedWidgets into smaller, focused ones. Use `select()` with Riverpod or Provider to subscribe to only the fields that affect a given widget. Override `updateShouldNotify` to return false when the relevant data hasn't changed.

```dart
// ❌ Every consumer rebuilds when ANY field of AppState changes
class AppStateScope extends InheritedWidget {
  @override
  bool updateShouldNotify(AppStateScope old) => appState != old.appState;
}

// ✅ Split by concern; consumers only rebuild when their slice changes
class ThemeScope extends InheritedWidget {
  @override
  bool updateShouldNotify(ThemeScope old) => theme != old.theme;
}

// Or with Riverpod:
final nameRef = ref.watch(userProvider.select((u) => u.name));
```
''',
    sources: [
      'https://api.flutter.dev/flutter/widgets/InheritedWidget-class.html',
      'https://docs.flutter.dev/data-and-backend/state-mgmt/options',
    ],
  ),

  KbEntry(
    id: 'helper-method-instead-of-widget',
    title: 'Helper Method Instead of Widget (No Rebuild Caching)',
    tags: ['rebuild', 'widget', 'pattern'],
    content: '''
Extracting UI into a private method (e.g. `_buildHeader()`) instead of a separate StatelessWidget means Flutter treats it as part of the parent's build output with no identity. The parent's setState() unconditionally rebuilds the helper's output even if its inputs haven't changed, and `const` cannot be used.

Diagnosis signals: Column or Row widgets rebuilding at high rates (>targetFps × 3); UI dominant; no async signals; many nested helper method calls in the stack.

Fix: Extract helper methods into proper StatelessWidget subclasses with const constructors. Flutter's element reconciliation can then skip rebuilding them when their props are unchanged.

```dart
// ❌ Rebuilt every time parent calls setState
Widget _buildAvatar(User user) =>
    CircleAvatar(backgroundImage: NetworkImage(user.avatarUrl));

// ✅ Flutter skips rebuild when props are identical
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user});
  final User user;
  @override
  Widget build(BuildContext context) =>
      CircleAvatar(backgroundImage: NetworkImage(user.avatarUrl));
}
```
''',
    sources: [
      'https://docs.flutter.dev/perf/best-practices#control-build-cost',
      'https://www.youtube.com/watch?v=IOyq-eTRhvo',
    ],
  ),

  KbEntry(
    id: 'value-notifier-whole-tree-rebuild',
    title: 'ValueNotifier / ChangeNotifier Rebuilding Whole Tree',
    tags: ['rebuild', 'state', 'notifier'],
    content: '''
Attaching a ValueListenableBuilder or ListenableBuilder high in the widget tree (e.g. on MaterialApp or a top-level Scaffold) causes the entire subtree to rebuild every time the notifier fires. This is functionally correct but performance-catastrophic for complex UIs.

Diagnosis signals: notifyListeners or ValueListenableBuilder in the CPU stack; rebuild count for MaterialApp or high-level widgets exceeds targetFps × 1.0; UI thread dominant.

Fix: Move the ValueListenableBuilder as close as possible to the widget that actually uses the value. Consider splitting the notifier into smaller, focused notifiers. Use Riverpod `ref.watch` or Provider `context.watch` which are scope-aware.

```dart
// ❌ Entire app rebuilds on every cart change
MaterialApp(
  home: ValueListenableBuilder<CartModel>(
    valueListenable: cartModel,
    builder: (_, cart, __) => MyHomePage(cart: cart),  // rebuilds all children
  ),
)

// ✅ Only the cart icon rebuilds
AppBar(
  actions: [
    ValueListenableBuilder<CartModel>(
      valueListenable: cartModel,
      builder: (_, cart, __) => CartIcon(count: cart.itemCount),
    ),
  ],
)
```
''',
    sources: [
      'https://api.flutter.dev/flutter/foundation/ValueListenableBuilder-class.html',
      'https://docs.flutter.dev/perf/best-practices',
    ],
  ),

  // ── Raster ────────────────────────────────────────────────────────────────

  KbEntry(
    id: 'raster-overdraw-opacity',
    title: 'Opacity Widget Causing saveLayer GPU Overdraw',
    tags: ['raster', 'opacity', 'gpu', 'overdraw'],
    content: '''
The Opacity widget forces the GPU to composite its subtree into an offscreen buffer (via saveLayer) before blending it with the scene. This is expensive — it allocates a full-resolution texture and requires two GPU passes. On large widgets or in lists, this can easily push the raster thread over the 16ms frame budget.

Diagnosis signals: raster thread dominant (rasterMs ≥ uiMs × 1.5); raster time > 8ms; Opacity widget in rebuild counts or saveLayer in the CPU stack.

Fix: Replace Opacity with FadeTransition (for animated opacity) or AnimatedOpacity (for setState-driven transitions). These use RenderObject-level compositing which is much cheaper. For static partially-opaque widgets, consider using a Color with alpha instead.

```dart
// ❌ Triggers saveLayer on every frame (double GPU pass)
Opacity(opacity: _animation.value, child: HeavyWidget())

// ✅ Uses hardware compositing path — no offscreen buffer
FadeTransition(opacity: _animation, child: HeavyWidget())

// For setState-driven fades:
AnimatedOpacity(opacity: _visible ? 1.0 : 0.0, duration: 300.ms, child: ...)

// For static partial opacity (no animation):
ColorFiltered(
  colorFilter: ColorFilter.mode(Colors.white.withValues(alpha: 0.5), BlendMode.modulate),
  child: HeavyWidget(),
)
```
''',
    sources: [
      'https://docs.flutter.dev/perf/rendering-performance#opacity-and-clipping',
      'https://api.flutter.dev/flutter/widgets/FadeTransition-class.html',
    ],
  ),

  KbEntry(
    id: 'raster-overdraw-clip',
    title: 'ClipRRect / ClipPath Causing Raster Overdraw',
    tags: ['raster', 'clip', 'overdraw', 'gpu'],
    content: '''
ClipRRect, ClipPath, and ClipOval with non-trivial clip shapes force the GPU to use saveLayer to isolate the clipped subtree. The cost grows with the area of the clipped widget and the number of layers beneath it.

Diagnosis signals: raster thread dominant; rasterMs > 8ms; ClipRRect, ClipPath, or ClipOval in rebuild counts.

Fix: Prefer Container with borderRadius and a BoxDecoration instead of ClipRRect for rounded corners. Use border-radius on Material or PhysicalModel. If ClipPath is required, mark the widget with a RepaintBoundary so it only repaints when its content changes, not when siblings animate.

```dart
// ❌ saveLayer on every frame
ClipRRect(
  borderRadius: BorderRadius.circular(12),
  child: Image.network(url),
)

// ✅ No saveLayer — GPU uses native corner rounding
Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
  ),
)
```
''',
    sources: [
      'https://docs.flutter.dev/perf/rendering-performance',
      'https://api.flutter.dev/flutter/widgets/ClipRRect-class.html',
    ],
  ),

  KbEntry(
    id: 'shader-compilation-jank',
    title: 'Shader Compilation Jank (First-Frame Hitches)',
    tags: ['raster', 'shader', 'impeller', 'gpu'],
    content: '''
Flutter compiles GLSL shaders on first use. When a new visual effect (gradient, blur, shadow, custom paint) is encountered for the first time, the GPU driver compiles the shader synchronously on the raster thread, causing a frame hitch of 50–500ms. This is most visible during app startup and first-time navigation.

Diagnosis signals: raster dominant (rasterMs ≥ uiMs × 2); rasterMs > 16ms; compileShader appears in the raster/UI stack; hitch occurs on first navigation or first use of a visual effect.

Fix: Use SkSL shader warm-up (Skia backend) or migrate to Impeller which eliminates runtime shader compilation by using offline-compiled MSL/SPIR-V shaders. For Skia: capture shaders with `--cache-sksl` and bundle them with the app.

```bash
# Capture SkSL shaders during a drive test
flutter run --profile --cache-sksl --purge-persistent-cache
# Bundle captured shaders into the app
flutter build apk --bundle-sksl-path flutter_01.sksl.json
```

For Impeller (iOS default since Flutter 3.10, Android opt-in):
```dart
// AndroidManifest.xml
<meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="true"/>
```
''',
    sources: [
      'https://docs.flutter.dev/perf/shader',
      'https://docs.flutter.dev/perf/impeller',
    ],
  ),

  KbEntry(
    id: 'backdrop-filter-overdraw',
    title: 'BackdropFilter / ImageFilter.blur GPU Overdraw',
    tags: ['raster', 'backdrop', 'blur', 'overdraw'],
    content: '''
BackdropFilter blurs everything behind it — Flutter must composite the entire scene behind the filter into an offscreen buffer, apply the Gaussian blur kernel, then composite the result back. The cost scales with the blur radius and the covered area. Multiple BackdropFilters stack multiplicatively.

Diagnosis signals: raster thread dominant (rasterMs ≥ uiMs × 1.5); BackdropFilter in widget rebuild counts or ImageFilter.blur in the CPU stack.

Fix: Minimise the blur area. Cache the blurred background as a static image if it doesn't change. Limit sigmaX/sigmaY values (> 10 gives diminishing visual returns with high cost). Use RepaintBoundary to isolate the blurred layer from frequently repainted siblings. Consider replacing with a frosted-glass shader that operates at lower cost.

```dart
// ❌ Full-scene composite on every frame
Stack(children: [
  background,
  BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
    child: SizedBox.expand(),
  ),
])

// ✅ Limit area + isolate with RepaintBoundary
RepaintBoundary(
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
    child: AlertDialog(...)  // small area only
  ),
)
```
''',
    sources: [
      'https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html',
      'https://docs.flutter.dev/perf/rendering-performance',
    ],
  ),

  KbEntry(
    id: 'missing-repaint-boundary',
    title: 'Missing RepaintBoundary on Animated Widget',
    tags: ['raster', 'repaint', 'animation', 'boundary'],
    content: '''
Without a RepaintBoundary, an animated widget that repaints every frame causes its entire parent layer to repaint too — including sibling widgets that haven't changed. For complex UIs with background content, this is a significant raster-thread waste.

Diagnosis signals: raster thread dominant; rasterMs > 8ms; AnimatedBuilder, AnimatedContainer, or TweenAnimationBuilder in rebuild counts but no RepaintBoundary.

Fix: Wrap independently animated widgets in RepaintBoundary. Flutter creates a new layer for the bounded widget, limiting repaints to just that layer on animation ticks.

```dart
// ❌ Entire screen repaints on every animation tick
Scaffold(
  body: Column(children: [
    HeavyStaticContent(),   // unnecessarily repainted
    AnimatedContainer(...), // the only thing that's changing
  ]),
)

// ✅ Only the animated widget's layer repaints
Scaffold(
  body: Column(children: [
    HeavyStaticContent(),
    RepaintBoundary(child: AnimatedContainer(...)),
  ]),
)
```
''',
    sources: [
      'https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html',
      'https://docs.flutter.dev/perf/rendering-performance#repaint-rainbow',
    ],
  ),

  // ── Async / Concurrency ────────────────────────────────────────────────────

  KbEntry(
    id: 'sync-io-on-ui-thread',
    title: 'Synchronous I/O Blocking the UI Thread',
    tags: ['async', 'io', 'isolate', 'critical'],
    content: '''
Dart's synchronous I/O methods (File.readAsStringSync, File.writeAsStringSync, Directory.listSync, etc.) block the calling thread until the OS completes the operation. When called on the UI thread, they freeze the app for the entire I/O duration — which can range from milliseconds to seconds depending on file size and storage speed.

Diagnosis signals: readAsStringSync, writeAsStringSync, existsSync, or listSync in the UI thread CPU stack; uiMs dominates and is ≥ rasterMs × 2; UI thread time > 16ms.

Fix: Always use async I/O on the UI thread. For file access: File.readAsString(), File.writeAsString(). For operations that must be synchronous, use Isolate.run() or compute() to run them off the main isolate.

```dart
// ❌ Freezes UI until file is read
final content = File(path).readAsStringSync();

// ✅ Non-blocking — UI thread is free during read
final content = await File(path).readAsString();

// For complex sync work:
final result = await Isolate.run(() {
  return expensiveSyncOperation();
});
```
''',
    sources: [
      'https://api.dart.dev/stable/dart-io/File-class.html',
      'https://docs.flutter.dev/perf/best-practices#avoid-expensive-synchronous-work-in-build',
    ],
  ),

  KbEntry(
    id: 'json-decode-ui-thread',
    title: 'JSON Decoding Blocking the UI Thread',
    tags: ['async', 'json', 'isolate', 'compute'],
    content: '''
json.decode() is a synchronous, CPU-bound operation that parses the entire JSON string in one go. For API responses larger than ~50 KB, this takes more than the 16ms frame budget and causes a visible stutter. The larger the payload, the longer the freeze.

Diagnosis signals: jsonDecode, json.decode, or convert.json in the UI CPU stack; uiMs > 8ms and UI dominant; no Isolate usage visible in the stack.

Fix: Move JSON decoding off the main isolate using `compute(jsonDecode, jsonString)` (Flutter) or `Isolate.run()` (pure Dart). For very large payloads, consider streaming JSON parsers.

```dart
// ❌ Blocks UI thread for large payloads
final data = jsonDecode(response.body) as Map<String, dynamic>;

// ✅ Runs in a separate isolate — UI stays responsive
final data = await compute(
  (String s) => jsonDecode(s) as Map<String, dynamic>,
  response.body,
);

// Or with Riverpod:
final dataProvider = FutureProvider.autoDispose((ref) async {
  final response = await dio.get('/api/data');
  return compute(jsonDecode, response.data);
});
```
''',
    sources: [
      'https://docs.flutter.dev/cookbook/networking/background-parsing',
      'https://api.flutter.dev/flutter/foundation/compute.html',
    ],
  ),

  KbEntry(
    id: 'heavy-compute-main-isolate',
    title: 'Heavy Computation on the Main Isolate',
    tags: ['async', 'compute', 'isolate', 'cpu'],
    content: '''
Dart is single-threaded per isolate. Any synchronous CPU-intensive operation (sorting large lists, image processing, cryptography, regex on large strings) runs on the main isolate's event loop and blocks all UI updates, animation ticks, and user input handling until it completes.

Diagnosis signals: UI thread dominant (uiMs ≥ rasterMs × 2) and uiMs > 16ms; no Isolate or compute() visible in the stack; the operation is not I/O (no file/network functions).

Fix: Offload to a worker isolate using `compute()` for one-shot tasks or `Isolate.spawn()` for long-running workers. The `flutter_isolate` package provides isolates with platform channel access.

```dart
// ❌ Sorts 100k items on main isolate — UI freezes
final sorted = items.toList()..sort((a, b) => a.score.compareTo(b.score));

// ✅ Sort in a separate isolate
final sorted = await Isolate.run(
  () => items.toList()..sort((a, b) => a.score.compareTo(b.score)),
);
```
''',
    sources: [
      'https://dart.dev/guides/language/concurrency',
      'https://api.flutter.dev/flutter/foundation/compute.html',
    ],
  ),

  KbEntry(
    id: 'platform-channel-ui-block',
    title: 'Platform Channel Call Blocking UI Thread',
    tags: ['async', 'platform-channel', 'native'],
    content: '''
MethodChannel.invokeMethod() is asynchronous but if the native side performs synchronous work that takes too long, or if the Dart side awaits the result in a way that starves the event loop, the UI can appear frozen. Additionally, calling platform channels from within a synchronous build pass is an error.

Diagnosis signals: MethodChannel, BasicMessageChannel, or EventChannel in the UI thread CPU stack; uiMs > 8ms and UI dominant; the call site is inside a build() method.

Fix: Never call platform channels from build(). Use FutureBuilder or pre-fetch results in initState(). For high-frequency calls, implement a dedicated background isolate communication channel (Flutter 3.7+ `IsolateNameServer` + `ReceivePort`).

```dart
// ❌ Platform channel in build — wrong on multiple levels
@override
Widget build(BuildContext context) {
  final result = channel.invokeMethod('getData');  // can't await here!
  ...
}

// ✅ Pre-fetch in initState, display with FutureBuilder
@override
void initState() {
  super.initState();
  _data = channel.invokeMethod<String>('getData');
}

@override
Widget build(BuildContext context) {
  return FutureBuilder<String>(
    future: _data,
    builder: (_, snap) => snap.hasData ? Text(snap.data!) : const Spinner(),
  );
}
```
''',
    sources: [
      'https://docs.flutter.dev/platform-integration/platform-channels',
      'https://docs.flutter.dev/perf/isolates',
    ],
  ),

  // ── Impeller ─────────────────────────────────────────────────────────────

  KbEntry(
    id: 'impeller-scroll-jank-ios',
    title: 'Impeller Scroll Jank on iOS (flutter/flutter#137992)',
    tags: ['impeller', 'ios', 'scroll', 'raster'],
    content: '''
A known Impeller regression on iOS causes scroll jank when lists contain widgets with complex paint operations (gradients, shadows, custom painters). The raster thread spikes because Impeller's tile-based rendering path handles certain draw calls less efficiently than Skia in specific scenarios.

Diagnosis signals: iOS device with Impeller enabled; raster thread dominant (rasterMs ≥ uiMs × 1.5) and rasterMs > 8ms; ListView, GridView, CustomScrollView, PageView, or SingleChildScrollView in the widget tree.

Fix: Add RepaintBoundary around complex list items. Simplify per-item paint operations — replace gradients with flat colors where possible; cache complex paint results using Picture.toImage(). Track flutter/flutter#137992 for upstream fixes.

```dart
// Wrap complex list items to isolate their paint layers
ListView.builder(
  itemBuilder: (ctx, i) => RepaintBoundary(
    key: ValueKey(items[i].id),
    child: ComplexListItem(items[i]),
  ),
)
```
''',
    sources: [
      'https://github.com/flutter/flutter/issues/137992',
      'https://docs.flutter.dev/perf/impeller',
    ],
  ),

  KbEntry(
    id: 'impeller-powervr-rogue-spike',
    title: 'Impeller PowerVR Rogue GPU Spike (flutter/flutter#161304)',
    tags: ['impeller', 'android', 'gpu', 'powervr'],
    content: '''
Devices with PowerVR Rogue series GPUs (common in older MediaTek and some Imagination Technologies chipsets) show severe raster spikes with Impeller on Android. The GPU driver's interaction with Impeller's Vulkan command buffers triggers unusually long GPU synchronisation stalls.

Diagnosis signals: Android device with Impeller enabled; GPU name contains "PowerVR Rogue"; raster thread ≥ UI thread × 2.

Fix: Disable Impeller for affected devices at runtime or in AndroidManifest.xml. File device-specific reports to flutter/flutter#161304 with GPU driver version information.

```dart
// Runtime detection and Impeller opt-out (Android)
// In AndroidManifest.xml:
// <meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false"/>

// Or runtime check:
if (defaultTargetPlatform == TargetPlatform.android) {
  // Use Skia path for affected devices
}
```
''',
    sources: [
      'https://github.com/flutter/flutter/issues/161304',
      'https://docs.flutter.dev/release/breaking-changes/android-impeller-preview',
    ],
  ),

  KbEntry(
    id: 'impeller-elevation-rounded-corners',
    title: 'Impeller Elevation + Rounded Corners Raster Spike (flutter/flutter#162312)',
    tags: ['impeller', 'ios', 'elevation', 'raster'],
    content: '''
On iOS with Impeller, combining Material elevation (shadows) with BorderRadius triggers expensive path tessellation on the raster thread. Impeller renders shadows by tessellating the shadow geometry — with rounded corners this generates significantly more vertices than Skia's RRectBlur shortcut. The Card widget with its default elevation is the most common trigger.

Diagnosis signals: iOS device with Impeller enabled; raster thread dominant (rasterMs ≥ uiMs × 1.5); Card, Material, or PhysicalModel in rebuild counts; BorderRadius in the CPU stack.

Fix: Remove or reduce elevation on Cards inside scrollable lists. Use a flat card design (elevation: 0) with border decoration instead. Or wrap Card in a RepaintBoundary to prevent siblings from triggering repaints.

```dart
// ❌ Expensive: elevation + rounded corners on every scroll frame
Card(
  elevation: 8,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  child: content,
)

// ✅ Flat card — no tessellation cost
Container(
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.grey.shade200),
  ),
  child: content,
)
```
''',
    sources: [
      'https://github.com/flutter/flutter/issues/162312',
      'https://docs.flutter.dev/perf/impeller',
    ],
  ),

  KbEntry(
    id: 'impeller-custom-scroll-view-android',
    title: 'Impeller CustomScrollView Android Jank (flutter/flutter#168788)',
    tags: ['impeller', 'android', 'scroll', 'raster'],
    content: '''
CustomScrollView with complex slivers shows increased raster-thread jank on Android with Impeller enabled compared to Skia. The issue is related to how Impeller handles the clipping and compositing of sliver children during fast fling gestures.

Diagnosis signals: Android device with Impeller enabled; CustomScrollView in rebuild counts; raster thread dominant during scroll.

Fix: Try disabling Impeller for the affected Android versions or simplify sliver content. Prefer SliverList over custom slivers where possible. Track flutter/flutter#168788 for upstream resolution.
''',
    sources: [
      'https://github.com/flutter/flutter/issues/168788',
    ],
  ),

  KbEntry(
    id: 'impeller-general-regression',
    title: 'General Impeller Performance Regression (flutter/flutter#169423)',
    tags: ['impeller', 'regression', 'raster'],
    content: '''
A broad class of scenes renders slower under Impeller than under Skia due to differences in rendering architecture. Impeller uses a tile-based deferred renderer which is faster for most workloads but slower for certain overdraw-heavy scenes or scenes with many small draw calls.

Diagnosis signals: Impeller enabled; raster thread dominant; rasterMs > 16ms; no more specific Impeller pattern matches (elevation, PowerVR, scroll).

Fix: Profile with GPU frame profiler to identify the expensive draw calls. Reduce overdraw with the Flutter Overdraw inspector. Consider per-widget RepaintBoundaries. File a bug at flutter/flutter#169423 with a reproducible case.
''',
    sources: [
      'https://github.com/flutter/flutter/issues/169423',
      'https://docs.flutter.dev/perf/ui-performance',
    ],
  ),

  // ── List / Grid ────────────────────────────────────────────────────────────

  KbEntry(
    id: 'listview-missing-extent',
    title: 'ListView Without itemExtent — Slow Layout',
    tags: ['list', 'listview', 'layout', 'performance'],
    content: '''
Without itemExtent or prototypeItem, ListView must lay out each item to determine its height before it can calculate the scroll extent and decide which items are visible. For long lists this means O(n) layout work even for items that are off-screen. With itemExtent, Flutter uses O(1) math to determine the visible range.

Diagnosis signals: UI thread dominant; ListView in rebuild counts; performLayout in the CPU stack; uiMs > 8ms.

Fix: Set itemExtent if all items have the same fixed height. Use prototypeItem if items have the same type but variable appearance. For truly variable heights, use SliverList with a more efficient delegate.

```dart
// ❌ O(n) layout — measures every item
ListView.builder(
  itemCount: 5000,
  itemBuilder: (ctx, i) => ListTile(title: Text('Item \$i')),
)

// ✅ O(1) layout — Flutter computes visible range mathematically
ListView.builder(
  itemCount: 5000,
  itemExtent: 56.0,  // fixed height for all items
  itemBuilder: (ctx, i) => ListTile(title: Text('Item \$i')),
)
```
''',
    sources: [
      'https://api.flutter.dev/flutter/widgets/ListView/itemExtent.html',
      'https://docs.flutter.dev/perf/best-practices#use-itemextent-in-listviews',
    ],
  ),

  KbEntry(
    id: 'listview-non-lazy',
    title: 'Non-Lazy ListView (All Children Built at Once)',
    tags: ['list', 'listview', 'lazy', 'performance'],
    content: '''
ListView(children: [...]) builds ALL child widgets immediately, even those far outside the viewport. For lists of more than ~20 items this is wasteful; for long lists it is a major jank source because layout, paint, and memory allocation happen for thousands of off-screen widgets.

Diagnosis signals: UI thread dominant; ListView in rebuild counts; SliverList in the CPU stack (indicating the full materialisation path); rebuild count for ListView exceeds targetFps × 0.5.

Fix: Replace ListView(children: [...]) with ListView.builder() which builds children lazily (on demand as they scroll into view). For known-size lists use ListView.separated() for a built-in divider.

```dart
// ❌ Builds all 1000 items immediately — O(n) startup cost
ListView(
  children: items.map((i) => ItemWidget(i)).toList(),
)

// ✅ Builds only ~20 visible items at a time — O(1) startup
ListView.builder(
  itemCount: items.length,
  itemBuilder: (ctx, i) => ItemWidget(items[i]),
)
```
''',
    sources: [
      'https://api.flutter.dev/flutter/widgets/ListView-class.html',
      'https://docs.flutter.dev/cookbook/lists/long-lists',
    ],
  ),

  KbEntry(
    id: 'list-missing-keys',
    title: 'Dynamic List Missing Widget Keys',
    tags: ['list', 'keys', 'rebuild', 'performance'],
    content: '''
When a dynamic list reorders or removes items without keys, Flutter's reconciliation algorithm cannot match old widget instances to new ones. It falls back to rebuilding and remounting every widget in the affected range, even items that didn't change. This causes unnecessary initState/dispose cycles and layout work.

Diagnosis signals: UI thread dominant; ListView or GridView in rebuild counts; updateChild in the CPU stack; ListTile or item widget rebuild count exceeds targetFps × 2.

Fix: Provide a key to every item in a dynamic list. ValueKey(item.id) is the simplest choice when items have stable unique IDs. ObjectKey works for object identity. Never use index-based keys for reorderable lists.

```dart
// ❌ Flutter cannot match items across reorder — rebuilds everything
ListView.builder(
  itemBuilder: (ctx, i) => ItemWidget(items[i]),
)

// ✅ Flutter matches by key — only changed items rebuild
ListView.builder(
  itemBuilder: (ctx, i) => ItemWidget(key: ValueKey(items[i].id), items[i]),
)
```
''',
    sources: [
      'https://api.flutter.dev/flutter/foundation/Key-class.html',
      'https://www.youtube.com/watch?v=kn0EOS-ZiIc',
    ],
  ),

  KbEntry(
    id: 'image-in-list-no-cache',
    title: 'Network Images in List Without Caching',
    tags: ['list', 'image', 'network', 'cache'],
    content: '''
Image.network() fetches and decodes images every time the widget is first built. In a ListView, items are recycled as you scroll — if images aren't cached, the same URLs are fetched repeatedly, causing network I/O on the UI thread and decode work on the raster thread. This produces both frame drops and data waste.

Diagnosis signals: UI or raster dominant depending on bottleneck; ListView or GridView in rebuilds; Image.network or NetworkImage in the CPU stack.

Fix: Use cached_network_image or flutter_cache_manager. Specify cacheWidth/cacheHeight to decode at display resolution rather than full resolution. Use a memory cache size appropriate for list item count × image size.

```dart
// ❌ Fetches and decodes on every list scroll
Image.network(item.imageUrl)

// ✅ Caches decoded images; serves from memory/disk on revisit
CachedNetworkImage(
  imageUrl: item.imageUrl,
  memCacheWidth: 200,   // decode at display size
  placeholder: (_, __) => const ShimmerBox(),
  errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
)
```
''',
    sources: [
      'https://pub.dev/packages/cached_network_image',
      'https://docs.flutter.dev/cookbook/images/cached-images',
    ],
  ),

  KbEntry(
    id: 'image-no-resize-cache',
    title: 'Images Decoded at Full Resolution (Missing cacheWidth/cacheHeight)',
    tags: ['image', 'raster', 'decode', 'memory'],
    content: '''
Flutter decodes network and asset images at their native resolution by default. A 4K image displayed at 100×100 logical pixels still allocates a 4K texture in GPU memory, consumes 4× the memory, and takes much longer to decode than necessary. The raster thread bears the decode cost via instantiateImageCodec / decodeImageFromList.

Diagnosis signals: raster thread dominant; instantiateImageCodec or decodeImageFromList in the CPU stack.

Fix: Specify cacheWidth and/or cacheHeight on Image widgets to instruct Flutter to resize during decode. Set these to the display size in physical pixels (logical size × devicePixelRatio).

```dart
// ❌ Decodes at full 4K resolution even for a 100pt thumbnail
Image.network(highResUrl)

// ✅ Decodes at 200px (100pt × 2x devicePixelRatio) — 16× less memory
Image.network(
  highResUrl,
  cacheWidth: 200,
  cacheHeight: 200,
)
```
''',
    sources: [
      'https://api.flutter.dev/flutter/widgets/Image/cacheWidth.html',
      'https://docs.flutter.dev/perf/best-practices#rendering-and-layout',
    ],
  ),
];
