# jankdoc_core

Shared models, interfaces, and 26 built-in rules that power the
[`jankdoc`](https://pub.dev/packages/jankdoc) Flutter DevTools extension.

Pure Dart — no Flutter dependency. Safe to import from CI runners.

## Contents

- **Models** — `TelemetryBatch`, `Diagnosis`, `Rule`, `Condition` AST,
  `Session`, `KbEntry`, `KbBundle`, `KbVersion`.
- **Interfaces** — `RuleProvider`, `RuleEngine`, `KbLoader`, `KbRegistry`,
  `LlmProvider`, `VectorStore`.
- **26 built-in rules** across build/rebuild, raster, impeller, async,
  list/grid categories.

## Usage

Most users should depend on [`jankdoc`](https://pub.dev/packages/jankdoc) —
this package is a transitive dependency. Import directly only if you're
building an alternative pipeline (e.g. running the rule engine standalone
in a CI runner).

```dart
import 'package:jankdoc_core/jankdoc_core.dart';

final provider = BuiltInRuleProvider();
final engine = RuleEngine(provider);
final matches = engine.match(telemetryBatch);
```

## License

MIT.
