import '../interfaces/rule_provider.dart';
import '../models/rule.dart';
import '../models/telemetry_batch.dart';

/// The Rule Pre-filter engine.
///
/// Evaluates all registered [Rule]s against a [TelemetryBatch] in priority
/// order and returns the first match. Evaluation completes in <5ms for the
/// current KB size (50 entries).
final class RuleEngine {
  RuleEngine(this._provider);

  final RuleProvider _provider;

  /// Returns the first matching rule in priority-descending order, or null.
  RuleMatch? evaluate(TelemetryBatch batch) {
    for (final rule in _provider.rules) {
      if (rule.matches(batch)) {
        return RuleMatch(rule: rule, batch: batch);
      }
    }
    return null;
  }

  /// Returns ALL matching rules — used for debugging and analytics.
  List<RuleMatch> evaluateAll(TelemetryBatch batch) => _provider.rules
      .where((r) => r.matches(batch))
      .map((r) => RuleMatch(rule: r, batch: batch))
      .toList();
}

/// The result of a successful rule evaluation.
final class RuleMatch {
  const RuleMatch({required this.rule, required this.batch});

  final Rule rule;
  final TelemetryBatch batch;
}
