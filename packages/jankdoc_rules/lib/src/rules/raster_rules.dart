import 'package:jankdoc_core/jankdoc_core.dart';

/// Rules for raster thread / GPU antipatterns.
///
/// Source: https://docs.flutter.dev/perf/rendering-performance
/// Source: Impeller migration guide
const List<Rule> rasterRules = [
  // ─── saveLayer / Opacity raster overdraw ────────────────────────────────
  Rule(
    id: 'raster-overdraw-opacity',
    patternId: 'raster-overdraw-opacity',
    confidence: 0.90,
    severity: Severity.high,
    priority: 10,
    condition: And([
      RasterDominant(),
      RasterThreadMs(greaterThan: 8.0),
      Or([
        WidgetType('Opacity'),
        StackContains('saveLayer'),
      ]),
    ]),
  ),

  // ─── ClipPath / ClipRRect overdraw ──────────────────────────────────────
  Rule(
    id: 'raster-overdraw-clip',
    patternId: 'raster-overdraw-clip',
    confidence: 0.88,
    severity: Severity.high,
    priority: 9,
    condition: And([
      RasterDominant(),
      RasterThreadMs(greaterThan: 8.0),
      Or([
        WidgetType('ClipRRect'),
        WidgetType('ClipPath'),
        WidgetType('ClipOval'),
      ]),
    ]),
  ),

  // ─── Shader compilation jank (first frame) ──────────────────────────────
  Rule(
    id: 'shader-compilation-jank',
    patternId: 'shader-compilation-jank',
    confidence: 0.85,
    severity: Severity.high,
    priority: 8,
    condition: And([
      RasterDominant(factor: 2.0),
      RasterThreadMs(greaterThan: 16.0),
      StackContains('compileShader'),
    ]),
  ),

  // ─── Excessive backdrop filter ──────────────────────────────────────────
  Rule(
    id: 'backdrop-filter-overdraw',
    patternId: 'backdrop-filter-overdraw',
    confidence: 0.87,
    severity: Severity.medium,
    priority: 7,
    condition: And([
      RasterDominant(),
      Or([
        WidgetType('BackdropFilter'),
        StackContains('ImageFilter.blur'),
      ]),
    ]),
  ),

  // ─── Missing RepaintBoundary on independently animated widget ───────────
  Rule(
    id: 'missing-repaint-boundary',
    patternId: 'missing-repaint-boundary',
    confidence: 0.83,
    severity: Severity.medium,
    priority: 6,
    condition: And([
      RasterDominant(),
      RasterThreadMs(greaterThan: 8.0),
      Not(WidgetType('RepaintBoundary')),
      Or([
        WidgetType('AnimatedBuilder'),
        WidgetType('AnimatedContainer'),
        WidgetType('TweenAnimationBuilder'),
      ]),
    ]),
  ),
];
