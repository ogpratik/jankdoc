import 'package:flutter/rendering.dart';

/// Counts render objects that force an offscreen layer (`saveLayer`) on the
/// raster thread, keyed by the widget that creates them.
///
/// Raster cost happens in the engine, so neither CPU samples nor rebuild
/// counts can see it: `Opacity` and friends are render-object widgets that
/// are updated, not rebuilt. The census is what lets the raster rules name
/// the widget responsible for a raster-bound frame.
abstract final class LayerCensus {
  /// Stop walking huge trees; the census only needs to establish presence.
  static const _maxNodes = 20000;

  static Map<String, int> take() {
    final counts = <String, int>{};
    var visited = 0;

    void visit(RenderObject node) {
      if (++visited > _maxNodes) return;
      final widget = switch (node) {
        RenderOpacity(:final opacity) when opacity > 0 && opacity < 1 =>
          'Opacity',
        RenderBackdropFilter() => 'BackdropFilter',
        RenderShaderMask() => 'ShaderMask',
        RenderClipRRect(clipBehavior: Clip.antiAliasWithSaveLayer) =>
          'ClipRRect',
        RenderClipPath(clipBehavior: Clip.antiAliasWithSaveLayer) => 'ClipPath',
        RenderClipOval(clipBehavior: Clip.antiAliasWithSaveLayer) => 'ClipOval',
        _ => null,
      };
      if (widget != null) counts[widget] = (counts[widget] ?? 0) + 1;
      node.visitChildren(visit);
    }

    for (final view in RendererBinding.instance.renderViews) {
      visit(view);
    }
    return counts;
  }
}
