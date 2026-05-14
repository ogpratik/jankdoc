# Rules are declarative data structures, not imperative Dart functions

Each Rule is a Dart constant object: a tree of composable Conditions plus a confidence score and KB Entry reference. Rules are defined as data — not as imperative `if` blocks — so they are:

- Testable in isolation without running the full pipeline
- Serialisable to JSON for community contribution and tooling
- Readable by non-Dart engineers (product managers, Flutter GDEs reviewing KB accuracy)
- Loaded at daemon startup from the KB directory; adding a rule requires no recompilation

The rule engine evaluates rules in priority order (severity desc, then confidence desc) and returns the first match. If multiple rules match, the highest-confidence match wins.

```dart
const Rule animatedBuilderStorm = Rule(
  id: 'excessive-rebuild-animated-builder',
  confidence: 0.95,
  patternId: 'excessive-rebuild-animated-builder',
  conditions: And([
    WidgetType('AnimatedBuilder'),
    ParentType(['ListView', 'GridView']),
    RebuildCount(greaterThan: FpsMultiple(factor: 1.5)),
  ]),
);
```

## Considered options

- **Imperative if/else blocks** (as shown in the build plan) — not scalable. 50 rules as nested if-statements are untestable in isolation, unreadable to non-engineers, and produce merge conflicts when community contributes new rules.
- **YAML rule files parsed at runtime** — attractive for community contribution, but adds a YAML schema validation layer and loses Dart's type system. Chosen against because the Dart constant approach is already declarative enough to be readable without losing type safety.
- **Declarative Dart constants** — selected. Type-safe, testable, serialisable, no parsing layer.
