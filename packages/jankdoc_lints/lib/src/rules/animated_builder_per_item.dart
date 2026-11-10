import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../utils.dart';

/// An `AnimatedBuilder` / `ListenableBuilder` created per item inside a
/// list's `itemBuilder`. Every tick rebuilds every visible item: a rebuild
/// storm that grows with the list.
///
/// KB: `animated-builder-rebuild-storm`.
class AnimatedBuilderPerItem extends AnalysisRule {
  static const LintCode code = LintCode(
    'animated_builder_per_item',
    "'{0}' is created for every list item, so each animation tick rebuilds "
        'every visible item.',
    correctionMessage:
        'Rebuild only the animated part: use a transition '
        'widget (RotationTransition, FadeTransition, …) or pass the '
        "AnimatedBuilder's child: for the static subtree. "
        '(JankDoc: animated-builder-rebuild-storm)',
    severity: DiagnosticSeverity.WARNING,
  );

  AnimatedBuilderPerItem()
    : super(
        name: 'animated_builder_per_item',
        description: 'Avoid an AnimatedBuilder per list item.',
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

  static const _builders = {'AnimatedBuilder', 'ListenableBuilder'};

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = constructedFlutterClass(node, _builders);
    if (name == null) return;
    // Only flag when the builder reuses the AnimatedBuilder's child: is not
    // given — with a child, the static subtree is already hoisted.
    if (namedArgument(node.argumentList, 'child') != null) return;
    if (!_isInsideItemBuilder(node)) return;
    rule.reportAtNode(node.constructorName, arguments: [name]);
  }

  static bool _isInsideItemBuilder(AstNode node) {
    for (AstNode? n = node.parent; n != null; n = n.parent) {
      if (n is FunctionExpression) {
        final parent = n.parent;
        if (parent is NamedArgument && parent.name.lexeme == 'itemBuilder') {
          return true;
        }
      }
      if (n is MethodDeclaration || n is FunctionDeclaration) return false;
    }
    return false;
  }
}
