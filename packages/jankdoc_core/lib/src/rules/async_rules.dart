import '../models/diagnosis.dart';
import '../models/rule.dart';

/// Rules for async / concurrency antipatterns.
const List<Rule> asyncRules = [
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
