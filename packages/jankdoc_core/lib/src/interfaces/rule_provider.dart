import '../models/rule.dart';

/// Provides the list of Rules available to the Rule Pre-filter.
///
/// The default implementation returns all built-in rules from jankdoc_rules.
/// Community plugins can register additional rules by providing their own
/// implementation and registering it with the daemon's DI container.
abstract interface class RuleProvider {
  /// All rules, sorted by [Rule.priority] descending then [Rule.confidence] descending.
  List<Rule> get rules;

  /// Look up a rule by its ID. Returns null if not found.
  Rule? findById(String id);
}
