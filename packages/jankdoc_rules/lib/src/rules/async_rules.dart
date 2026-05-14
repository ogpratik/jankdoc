import 'package:jankdoc_core/jankdoc_core.dart';

/// Rules for async / concurrency antipatterns.
///
/// Source: Slava Egorov — What is an Isolate anyway? (FlutterCon EU 2024)
/// Source: https://docs.flutter.dev/perf/best-practices
const List<Rule> asyncRules = [
  // ─── Synchronous I/O on the UI thread ────────────────────────────────────
  Rule(
    id: 'sync-io-on-ui-thread',
    patternId: 'sync-io-on-ui-thread',
    confidence: 0.93,
    severity: Severity.critical,
    priority: 20,
    condition: And([
      UiDominant(factor: 2.0),
      Or([
        StackContains('readAsStringSync'),
        StackContains('writeAsStringSync'),
        StackContains('existsSync'),
        StackContains('listSync'),
      ]),
    ]),
  ),

  // ─── JSON decode on the UI thread ───────────────────────────────────────
  Rule(
    id: 'json-decode-ui-thread',
    patternId: 'json-decode-ui-thread',
    confidence: 0.92,
    severity: Severity.high,
    priority: 18,
    condition: And([
      UiDominant(),
      UiThreadMs(greaterThan: 8.0),
      Or([
        StackContains('jsonDecode'),
        StackContains('json.decode'),
        StackContains('convert.json'),
      ]),
    ]),
  ),

  // ─── Heavy computation without Isolate ──────────────────────────────────
  Rule(
    id: 'heavy-compute-main-isolate',
    patternId: 'heavy-compute-main-isolate',
    confidence: 0.87,
    severity: Severity.high,
    priority: 12,
    condition: And([
      UiDominant(factor: 2.0),
      UiThreadMs(greaterThan: 16.0),
      Not(StackContains('Isolate')),
      Not(StackContains('compute(')),
    ]),
  ),

  // ─── Platform channel call blocks UI thread ─────────────────────────────
  Rule(
    id: 'platform-channel-ui-block',
    patternId: 'platform-channel-ui-block',
    confidence: 0.88,
    severity: Severity.high,
    priority: 14,
    condition: And([
      UiDominant(),
      UiThreadMs(greaterThan: 8.0),
      Or([
        StackContains('MethodChannel'),
        StackContains('BasicMessageChannel'),
        StackContains('EventChannel'),
      ]),
    ]),
  ),
];
