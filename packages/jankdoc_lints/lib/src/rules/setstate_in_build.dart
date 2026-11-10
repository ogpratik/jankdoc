import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../utils.dart';

/// `setState` called from `build()` — directly, or scheduled from it via a
/// post-frame callback / microtask / timer. Every build triggers another
/// build: an endless rebuild loop that saturates the UI thread.
///
/// KB: `setstate-in-build`.
class SetStateInBuild extends AnalysisRule {
  static const LintCode code = LintCode(
    'setstate_in_build',
    'setState() is called from build(), so every build schedules another '
        'build — an endless rebuild loop on the UI thread.',
    correctionMessage:
        'Move the state change to initState(), '
        'didChangeDependencies(), or an event handler, or derive the value '
        'in build() without calling setState(). (JankDoc: setstate-in-build)',
    severity: DiagnosticSeverity.WARNING,
  );

  SetStateInBuild()
    : super(
        name: 'setstate_in_build',
        description: 'Avoid calling or scheduling setState() from build().',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'setState') return;
    final target = node.target;
    if (target != null && target is! ThisExpression) return;
    if (!isFrom(node.methodName.element, 'package:flutter/')) return;

    final build = enclosingBuild(
      node,
      through: const {ClosureRole.buildTime, ClosureRole.scheduledFromBuild},
    );
    if (build != null) rule.reportAtNode(node.methodName);
  }
}
