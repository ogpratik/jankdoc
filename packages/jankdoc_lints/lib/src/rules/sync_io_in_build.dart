import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../utils.dart';

/// Blocking `dart:io` calls (`readAsStringSync`, `existsSync`, …) during
/// build. Disk latency lands directly on the UI thread's frame budget.
///
/// KB: `sync-io-on-ui-thread`.
class SyncIoInBuild extends AnalysisRule {
  static const LintCode code = LintCode(
    'sync_io_in_build',
    "'{0}' blocks the UI thread while build() runs.",
    correctionMessage:
        'Load the data once, asynchronously (initState() + '
        'FutureBuilder, or a state-management layer), and read the cached '
        'result in build(). (JankDoc: sync-io-on-ui-thread)',
    severity: DiagnosticSeverity.WARNING,
  );

  SyncIoInBuild()
    : super(
        name: 'sync_io_in_build',
        description: 'Avoid synchronous file I/O during build().',
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
    final name = node.methodName.name;
    if (!name.endsWith('Sync')) return;
    if (!isFrom(node.methodName.element, 'dart:io')) return;
    if (enclosingBuild(node) == null) return;
    rule.reportAtNode(node.methodName, arguments: [name]);
  }
}
