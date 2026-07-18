import '../models/diagnosis.dart';
import '../models/rule.dart';

/// Rules for list, grid, and sliver antipatterns.
const List<Rule> listGridRules = [
  Rule(
    id: 'listview-missing-extent',
    patternId: 'listview-missing-extent',
    confidence: 0.86,
    severity: Severity.medium,
    priority: 7,
    condition: And([
      UiDominant(),
      WidgetType('ListView'),
      StackContains('performLayout'),
      UiThreadMs(greaterThan: 8.0),
    ]),
  ),
  Rule(
    id: 'listview-non-lazy',
    patternId: 'listview-non-lazy',
    confidence: 0.89,
    severity: Severity.high,
    priority: 10,
    condition: And([
      UiDominant(),
      WidgetType('ListView'),
      StackContains('SliverList'),
      RebuildStorm(widgetType: 'ListView', factor: 0.5),
    ]),
  ),
  Rule(
    id: 'list-missing-keys',
    patternId: 'list-missing-keys',
    confidence: 0.84,
    severity: Severity.medium,
    priority: 6,
    condition: And([
      UiDominant(),
      Or([
        WidgetType('ListView'),
        WidgetType('GridView'),
      ]),
      StackContains('updateChild'),
      RebuildStorm(widgetType: 'ListTile', factor: 2.0),
    ]),
  ),
  Rule(
    id: 'image-in-list-no-cache',
    patternId: 'image-in-list-no-cache',
    confidence: 0.87,
    severity: Severity.high,
    priority: 9,
    condition: And([
      Or([RasterDominant(), UiDominant()]),
      Or([
        WidgetType('ListView'),
        WidgetType('GridView'),
      ]),
      Or([
        StackContains('Image.network'),
        StackContains('NetworkImage'),
      ]),
    ]),
  ),
  Rule(
    id: 'image-no-resize-cache',
    patternId: 'image-no-resize-cache',
    confidence: 0.85,
    severity: Severity.medium,
    priority: 7,
    condition: And([
      RasterDominant(),
      Or([
        StackContains('instantiateImageCodec'),
        StackContains('decodeImageFromList'),
      ]),
    ]),
  ),
];
