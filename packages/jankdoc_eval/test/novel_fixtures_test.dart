import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:jankdoc_eval/jankdoc_eval.dart';
import 'package:test/test.dart';

/// Guardrail: every fixture in [NovelFixtures] must **not** be caught by any
/// built-in rule.
///
/// If a rule ever fires on one of these, either:
///   - the fixture is now covered by a rule (delete from novel set), or
///   - the rule has become too broad (tighten its condition).
///
/// Either way the LLM baseline is measuring the wrong thing, so this test
/// fails fast.
void main() {
  final engine = RuleEngine(BuiltInRuleProvider());

  group('NovelFixtures — no rule should match', () {
    for (final fixture in NovelFixtures.all) {
      test(fixture.id, () {
        final match = engine.evaluate(fixture.batch);
        expect(
          match,
          isNull,
          reason: 'Novel fixture "${fixture.id}" is now caught by rule '
              '"${match?.rule.id}" — move it to EvalFixtures or tighten '
              'the matching rule.',
        );
      });
    }
  });

  test('NovelFixtures.all has exactly 5 cases (matches LAUNCH_PLAN 2.3.3)',
      () {
    expect(NovelFixtures.all.length, 5);
  });

  test('every novel case asserts an LLM-appropriate pattern id + sources', () {
    for (final fixture in NovelFixtures.all) {
      expect(
        fixture.assertions.whereType<PatternIdAssertion>().length,
        1,
        reason: '${fixture.id} must assert exactly one expected pattern id',
      );
      expect(
        fixture.assertions.whereType<HasSourcesAssertion>(),
        isNotEmpty,
        reason: '${fixture.id} must require the LLM to cite KB sources',
      );
    }
  });
}
