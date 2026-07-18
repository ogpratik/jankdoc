import '../models/diagnosis.dart';
import '../models/rule.dart';

/// Rules for widget build / rebuild antipatterns.
const List<Rule> buildRebuildRules = [
  Rule(
    id: 'animated-builder-rebuild-storm',
    patternId: 'animated-builder-rebuild-storm',
    confidence: 0.95,
    severity: Severity.high,
    priority: 10,
    condition: And([
      WidgetType('AnimatedBuilder'),
      AnyWidgetType(['ListView', 'GridView', 'SliverList', 'SliverGrid']),
      RebuildStorm(widgetType: 'AnimatedBuilder', factor: 1.5),
    ]),
  ),
  Rule(
    id: 'setstate-in-build',
    patternId: 'setstate-in-build',
    confidence: 0.92,
    severity: Severity.critical,
    priority: 20,
    condition: And([
      UiDominant(),
      StackContains('setState'),
      StackContains('build'),
    ]),
  ),
  Rule(
    id: 'missing-const-constructor',
    patternId: 'missing-const-constructor',
    confidence: 0.85,
    severity: Severity.medium,
    priority: 5,
    condition: And([
      UiDominant(),
      RebuildStorm(widgetType: 'Scaffold', factor: 2.0),
    ]),
  ),
  Rule(
    id: 'expensive-computation-in-build',
    patternId: 'expensive-computation-in-build',
    confidence: 0.88,
    severity: Severity.high,
    priority: 8,
    condition: And([
      UiDominant(factor: 2.0),
      Or([
        StackContains('jsonDecode'),
        StackContains('jsonEncode'),
        StackContains('compute'),
        StackContains('Isolate.run'),
      ]),
    ]),
  ),
  Rule(
    id: 'inherited-widget-over-rebuild',
    patternId: 'inherited-widget-over-rebuild',
    confidence: 0.87,
    severity: Severity.high,
    priority: 7,
    condition: And([
      UiDominant(),
      Or([
        StackContains('didChangeDependencies'),
        StackContains('dependOnInheritedWidgetOfExactType'),
      ]),
      RebuildStorm(widgetType: 'Consumer', factor: 2.0),
    ]),
  ),
  Rule(
    id: 'helper-method-instead-of-widget',
    patternId: 'helper-method-instead-of-widget',
    confidence: 0.83,
    severity: Severity.medium,
    priority: 4,
    condition: And([
      UiDominant(),
      RebuildStorm(widgetType: 'Column', factor: 3.0),
      Not(WidgetType('StatelessWidget')),
    ]),
  ),
  Rule(
    id: 'value-notifier-whole-tree-rebuild',
    patternId: 'value-notifier-whole-tree-rebuild',
    confidence: 0.86,
    severity: Severity.high,
    priority: 8,
    condition: And([
      UiDominant(),
      Or([
        StackContains('notifyListeners'),
        StackContains('ValueListenableBuilder'),
      ]),
      RebuildStorm(widgetType: 'MaterialApp', factor: 1.0),
    ]),
  ),
];
