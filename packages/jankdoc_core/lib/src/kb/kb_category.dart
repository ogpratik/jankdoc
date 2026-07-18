/// The performance antipattern category for a KB Entry.
///
/// Categories map to distinct diagnostic signals and rule families.
/// An entry belongs to exactly one category; related categories are
/// surfaced to the user through the Diagnosis explanation.
enum KbCategory {
  /// Unnecessary widget rebuilds — setState on too-wide a subtree,
  /// missing const constructors, over-broad InheritedWidget scopes.
  rebuild,

  /// Expensive layout passes — deep nesting, unconstrained intrinsics,
  /// complex CustomMultiChildLayout.
  layout,

  /// Raster-thread shader compilation stutter — missing SkSL warm-up,
  /// Impeller pipeline compilation, first-frame stutter.
  shaderCompilation,

  /// Raster-thread overdraw — excessive layer count, transparent
  /// backgrounds, nested opacity widgets.
  overdraw,

  /// UI-thread work that belongs on a background isolate — JSON decoding,
  /// image processing, synchronous file I/O on the main thread.
  mainThreadJank,

  /// Platform channel round-trip latency causing UI thread stalls.
  platformChannel,

  /// Dart heap pressure causing GC pauses — large allocation rates,
  /// long-lived caches, image byte array mismanagement.
  memoryPressure,

  /// Impeller-specific regressions — path rendering quirks, layer
  /// atlas overflow, GPU memory spikes on API 29+.
  impeller,

  /// List and grid performance — non-lazy rendering, heavy item builders,
  /// missing `itemExtent` on uniform lists.
  listGrid,

  /// Animation jank — non-constant AnimationController ticks, heavy
  /// build() inside AnimatedBuilder, excessive repaint area.
  animation,

  /// Image decoding and caching — missing `cacheWidth`/`cacheHeight`,
  /// synchronous asset loading, unbounded ImageCache.
  imageLoading,
}
