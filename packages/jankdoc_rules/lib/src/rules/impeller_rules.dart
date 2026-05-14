import 'package:jankdoc_core/jankdoc_core.dart';

/// Rules specific to the Impeller rendering backend.
///
/// The v1 launch wedge: 5 entries seeded from open flutter/flutter issues.
/// Sources:
///   #137992 — scroll jank on iOS (wonderous app)
///   #161304 — PowerVR Rogue GE8320 perf
///   #162312 — elevation + rounded corners
///   #168788 — CustomScrollView Android jank
///   #169423 — general Impeller regression vs Skia
const List<Rule> impellerRules = [
  // ─── Impeller scroll jank iOS (#137992) ─────────────────────────────────
  Rule(
    id: 'impeller-scroll-jank-ios',
    patternId: 'impeller-scroll-jank-ios',
    confidence: 0.92,
    severity: Severity.high,
    priority: 15,
    condition: And([
      ImpellerEnabled(),
      Platform(TargetPlatform.ios),
      RasterDominant(),
      RasterThreadMs(greaterThan: 8.0),
      AnyWidgetType([
        'ListView',
        'GridView',
        'CustomScrollView',
        'PageView',
        'SingleChildScrollView',
      ]),
    ]),
  ),

  // ─── PowerVR Rogue GPU spike (#161304) ──────────────────────────────────
  Rule(
    id: 'impeller-powervr-rogue-spike',
    patternId: 'impeller-powervr-rogue-spike',
    confidence: 0.90,
    severity: Severity.high,
    priority: 15,
    condition: And([
      ImpellerEnabled(),
      GpuContains('PowerVR Rogue'),
      RasterDominant(factor: 2.0),
    ]),
  ),

  // ─── Elevation + rounded corners (#162312) ──────────────────────────────
  Rule(
    id: 'impeller-elevation-rounded-corners',
    patternId: 'impeller-elevation-rounded-corners',
    confidence: 0.88,
    severity: Severity.medium,
    priority: 12,
    condition: And([
      ImpellerEnabled(),
      RasterDominant(),
      Or([
        And([
          WidgetType('Material'),
          StackContains('elevation'),
          StackContains('BorderRadius'),
        ]),
        And([
          WidgetType('Card'),
          StackContains('BorderRadius'),
        ]),
        WidgetType('PhysicalModel'),
      ]),
    ]),
  ),

  // ─── CustomScrollView Android jank (#168788) ────────────────────────────
  Rule(
    id: 'impeller-custom-scroll-view-android',
    patternId: 'impeller-custom-scroll-view-android',
    confidence: 0.89,
    severity: Severity.high,
    priority: 14,
    condition: And([
      ImpellerEnabled(),
      Platform(TargetPlatform.android),
      WidgetType('CustomScrollView'),
      RasterDominant(),
    ]),
  ),

  // ─── General Impeller regression vs Skia (#169423) ──────────────────────
  /// Broad fallback: Impeller is enabled and frames are consistently over
  /// budget, but no more specific Impeller pattern matched.
  Rule(
    id: 'impeller-general-regression',
    patternId: 'impeller-general-regression',
    confidence: 0.82,
    severity: Severity.medium,
    priority: 5,
    condition: And([
      ImpellerEnabled(),
      RasterDominant(),
      RasterThreadMs(greaterThan: 16.0),
    ]),
  ),
];
