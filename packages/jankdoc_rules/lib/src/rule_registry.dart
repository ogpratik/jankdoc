import 'package:collection/collection.dart';
import 'package:jankdoc_core/jankdoc_core.dart';

import 'rules/async_rules.dart';
import 'rules/build_rebuild_rules.dart';
import 'rules/impeller_rules.dart';
import 'rules/list_grid_rules.dart';
import 'rules/raster_rules.dart';

/// The built-in rule registry — implements [RuleProvider].
///
/// Rules are sorted once at construction time:
///   1. [Rule.priority] descending
///   2. [Rule.confidence] descending
///   3. [Rule.id] ascending (stable tie-breaker)
final class BuiltInRuleProvider implements RuleProvider {
  BuiltInRuleProvider() : _sorted = _buildSortedRules();

  static List<Rule> _buildSortedRules() {
    final all = [
      ...impellerRules,   // Impeller first — most time-sensitive in 2026
      ...buildRebuildRules,
      ...rasterRules,
      ...asyncRules,
      ...listGridRules,
    ];

    return all.sortedWith((a, b) {
      // Priority descending
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      // Confidence descending
      final byConf = b.confidence.compareTo(a.confidence);
      if (byConf != 0) return byConf;
      // Stable tie-breaker
      return a.id.compareTo(b.id);
    });
  }

  final List<Rule> _sorted;

  @override
  List<Rule> get rules => _sorted;

  @override
  Rule? findById(String id) =>
      _sorted.firstWhereOrNull((r) => r.id == id);
}

extension on List<Rule> {
  List<Rule> sortedWith(Comparator<Rule> comparator) {
    final copy = [...this];
    copy.sort(comparator);
    return copy;
  }
}
