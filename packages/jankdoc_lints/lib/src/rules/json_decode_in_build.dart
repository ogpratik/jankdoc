import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../utils.dart';

/// `jsonDecode` / `json.decode` during build. Parsing re-runs on every
/// rebuild, and large payloads blow the frame budget.
///
/// KB: `json-decode-ui-thread`.
class JsonDecodeInBuild extends AnalysisRule {
  static const LintCode code = LintCode(
    'json_decode_in_build',
    'JSON is decoded inside build(), so it is re-parsed on the UI thread on '
        'every rebuild.',
    correctionMessage:
        'Decode once outside build(); for large payloads use '
        'compute(jsonDecode, body) or Isolate.run(). '
        '(JankDoc: json-decode-ui-thread)',
    severity: DiagnosticSeverity.WARNING,
  );

  JsonDecodeInBuild()
    : super(
        name: 'json_decode_in_build',
        description: 'Avoid decoding JSON during build().',
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
    if (name != 'jsonDecode' && name != 'decode' && name != 'convert') return;
    final element = node.methodName.element;
    if (!isFrom(element, 'dart:convert')) return;
    // `decode`/`convert` exist on every codec; only flag the JSON ones.
    if (name != 'jsonDecode') {
      final type = node.realTarget?.staticType?.element?.name;
      if (type != 'JsonCodec' && type != 'JsonDecoder') return;
    }
    if (enclosingBuild(node) == null) return;
    rule.reportAtNode(node.methodName);
  }
}
