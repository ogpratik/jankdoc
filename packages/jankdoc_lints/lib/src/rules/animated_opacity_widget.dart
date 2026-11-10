import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../utils.dart';

/// An `Opacity` widget whose opacity is driven by an `Animation`'s value.
/// Each tick rebuilds the subtree and repaints it through `saveLayer` —
/// expensive raster work every frame.
///
/// KB: `raster-overdraw-opacity`.
class AnimatedOpacityWidget extends AnalysisRule {
  static const LintCode code = LintCode(
    'animated_opacity_widget',
    'Opacity is animated by rebuilding with an Animation value, forcing a '
        'rebuild and saveLayer every frame.',
    correctionMessage:
        'Use FadeTransition(opacity: animation), which '
        'animates on the compositor without rebuilding. '
        '(JankDoc: raster-overdraw-opacity)',
    severity: DiagnosticSeverity.WARNING,
  );

  AnimatedOpacityWidget()
    : super(
        name: 'animated_opacity_widget',
        description: 'Use FadeTransition instead of animating Opacity.',
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

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (constructedFlutterClass(node, const {'Opacity'}) == null) return;
    final opacity = namedArgument(node.argumentList, 'opacity');
    if (opacity == null) return;
    if (!readsAnimationValue(opacity.argumentExpression)) return;
    rule.reportAtNode(node.constructorName);
  }
}
