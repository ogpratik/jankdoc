import 'package:collection/collection.dart';

import '../interfaces/rule_provider.dart';
import '../models/rule.dart';
import 'async_rules.dart';
import 'build_rebuild_rules.dart';
import 'impeller_rules.dart';
import 'list_grid_rules.dart';
import 'raster_rules.dart';

/// The built-in rule registry.
///
/// Rules are loaded from typed Dart constants until the [KbBundle] system
/// is in place. Once `jankdoc-kb` ships YAML rule definitions, this class
/// will be replaced by a [KbBundle]-backed [RuleProvider].
///
/// Sorted once at construction: priority desc → confidence desc → id asc.
final class BuiltInRuleProvider implements RuleProvider {
  BuiltInRuleProvider() : _sorted = _buildSortedRules();

  static List<Rule> _buildSortedRules() {
    final all = [
      ...impellerRules,
      ...buildRebuildRules,
      ...rasterRules,
      ...asyncRules,
      ...listGridRules,
    ];
    return all.sortedWith((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      final byConf = b.confidence.compareTo(a.confidence);
      if (byConf != 0) return byConf;
      return a.id.compareTo(b.id);
    });
  }

  final List<Rule> _sorted;

  @override
  List<Rule> get rules => _sorted;

  @override
  Rule? findById(String id) => _sorted.firstWhereOrNull((r) => r.id == id);
}

extension on List<Rule> {
  List<Rule> sortedWith(Comparator<Rule> comparator) {
    final copy = [...this];
    copy.sort(comparator);
    return copy;
  }
}
