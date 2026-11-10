import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../utils.dart';

/// `Clip.antiAliasWithSaveLayer` allocates an offscreen layer for every
/// clipped paint. It is almost never visually distinguishable from
/// `Clip.antiAlias`, which needs no layer.
///
/// KB: `raster-overdraw-clip`.
class ClipSaveLayer extends AnalysisRule {
  static const LintCode code = LintCode(
    'clip_save_layer',
    'Clip.antiAliasWithSaveLayer allocates an offscreen layer on every paint.',
    correctionMessage:
        'Use Clip.antiAlias (or Clip.hardEdge). '
        '(JankDoc: raster-overdraw-clip)',
    severity: DiagnosticSeverity.WARNING,
  );

  ClipSaveLayer()
    : super(
        name: 'clip_save_layer',
        description: 'Avoid Clip.antiAliasWithSaveLayer.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry.addPrefixedIdentifier(this, visitor);
    registry.addPropertyAccess(this, visitor);
    registry.addDotShorthandPropertyAccess(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  void _check(SimpleIdentifier name) {
    if (name.name != 'antiAliasWithSaveLayer') return;
    final element = name.element;
    if (element?.enclosingElement?.name != 'Clip') return;
    // Declared in dart:ui; package:flutter only re-exports it.
    if (!isFrom(element, 'dart:ui') && !isFrom(element, 'package:flutter/')) {
      return;
    }
    rule.reportAtNode(name);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) =>
      _check(node.identifier);

  @override
  void visitPropertyAccess(PropertyAccess node) => _check(node.propertyName);

  @override
  void visitDotShorthandPropertyAccess(DotShorthandPropertyAccess node) =>
      _check(node.propertyName);
}
