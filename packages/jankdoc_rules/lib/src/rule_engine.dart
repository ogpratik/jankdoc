import 'package:jankdoc_core/jankdoc_core.dart';

/// The Rule Pre-filter engine.
///
/// Evaluates all registered [Rule]s against a [TelemetryBatch] in priority
/// order and returns the first match. The entire evaluation completes in <5ms
/// for the current KB size.
final class RuleEngine {
  RuleEngine(this._provider);

  final RuleProvider _provider;

  /// Evaluate all rules and return the first match, or null if none match.
  ///
  /// Rules are evaluated in [Rule.priority] descending order.
  /// On a match, the engine stops — only the highest-priority rule fires.
  RuleMatch? evaluate(TelemetryBatch batch) {
    for (final rule in _provider.rules) {
      if (rule.matches(batch)) {
        return RuleMatch(rule: rule, batch: batch);
      }
    }
    return null;
  }

  /// Evaluate all rules and return ALL matches (for debugging / analytics).
  List<RuleMatch> evaluateAll(TelemetryBatch batch) => _provider.rules
      .where((r) => r.matches(batch))
      .map((r) => RuleMatch(rule: r, batch: batch))
      .toList();
}

/// The result of a successful rule match.
final class RuleMatch {
  const RuleMatch({required this.rule, required this.batch});

  final Rule rule;
  final TelemetryBatch batch;
}
