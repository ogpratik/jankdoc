import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../utils.dart';

/// `ListView(children: List.generate(...))` (or `.map(...).toList()`, or a
/// collection-`for`). Every child is built and laid out up front, including
/// the off-screen ones; `ListView.builder` builds only what is visible.
///
/// KB: `listview-non-lazy`.
class NonLazyList extends AnalysisRule {
  static const LintCode code = LintCode(
    'non_lazy_list',
    "'{0}' builds every child eagerly, including off-screen ones.",
    correctionMessage:
        "Use '{0}.builder' so only visible children are "
        'built. (JankDoc: listview-non-lazy)',
    severity: DiagnosticSeverity.WARNING,
  );

  NonLazyList()
    : super(
        name: 'non_lazy_list',
        description:
            'Use ListView.builder / GridView.builder for '
            'generated children.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addInstanceCreationExpression(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  static const _scrollables = {'ListView', 'GridView'};

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = constructedFlutterClass(node, _scrollables);
    if (name == null) return;
    // Named constructors (.builder, .separated, .count…) other than GridView's
    // eager ones are already lazy or take no `children`.
    final ctor = node.constructorName.name?.name;
    if (ctor != null && !(name == 'GridView' && ctor == 'count')) return;
    final children = namedArgument(node.argumentList, 'children');
    if (children == null) return;
    if (!_isGenerated(children.argumentExpression)) return;
    rule.reportAtNode(node.constructorName, arguments: [name]);
  }

  static bool _isGenerated(Expression e) {
    if (isListGenerate(e)) return true;
    if (e is MethodInvocation && e.methodName.name == 'toList') {
      final target = e.realTarget;
      return target is MethodInvocation && target.methodName.name == 'map';
    }
    if (e is ListLiteral) {
      return e.elements.any((el) => el is ForElement);
    }
    return false;
  }
}
