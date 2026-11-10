import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../utils.dart';

InstanceCreationExpression? _creationAt(AstNode node) =>
    node.thisOrAncestorOfType<InstanceCreationExpression>();

/// `Clip.antiAliasWithSaveLayer` → `Clip.antiAlias`.
class UseClipAntiAlias extends ResolvedCorrectionProducer {
  static const _kind = FixKind(
    'jankdoc.fix.useClipAntiAlias',
    DartFixKindPriority.standard,
    'Use Clip.antiAlias',
  );

  UseClipAntiAlias({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.acrossSingleFile;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final name = node;
    if (name is! SimpleIdentifier || name.name != 'antiAliasWithSaveLayer') {
      return;
    }
    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleReplacement(range.node(name), 'antiAlias');
    });
  }
}

/// `Opacity(opacity: anim.value, …)` → `FadeTransition(opacity: anim, …)`.
///
/// Only offered when the opacity is exactly `<animation>.value`; computed
/// opacities need a hand-written Tween/CurvedAnimation.
class UseFadeTransition extends ResolvedCorrectionProducer {
  static const _kind = FixKind(
    'jankdoc.fix.useFadeTransition',
    DartFixKindPriority.standard,
    'Replace with FadeTransition',
  );

  UseFadeTransition({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final creation = _creationAt(node);
    if (creation == null) return;
    final opacity = namedArgument(creation.argumentList, 'opacity');
    if (opacity == null) return;
    final animation = animationOfValueRead(opacity.argumentExpression);
    if (animation == null) return;
    final typeName = creation.constructorName.type.name;
    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleReplacement(range.token(typeName), 'FadeTransition');
      builder.addSimpleReplacement(
        range.node(opacity.argumentExpression),
        utils.getNodeText(animation),
      );
    });
  }
}

/// `ListView(children: List.generate(n, (i) => w))`
/// → `ListView.builder(itemCount: n, itemBuilder: (context, i) => w)`.
class UseListViewBuilder extends ResolvedCorrectionProducer {
  static const _kind = FixKind(
    'jankdoc.fix.useListViewBuilder',
    DartFixKindPriority.standard,
    'Convert to ListView.builder',
  );

  UseListViewBuilder({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final creation = _creationAt(node);
    if (creation == null) return;
    final ctor = creation.constructorName;
    if (ctor.type.name.lexeme != 'ListView' || ctor.name != null) return;
    final children = namedArgument(creation.argumentList, 'children');
    if (children == null) return;
    final args = listGenerateArguments(children.argumentExpression)?.arguments;
    if (args == null) return;
    if (args.length != 2 || args.any((a) => a is NamedArgument)) return;
    final count = args[0].argumentExpression;
    final generator = args[1].argumentExpression;
    if (generator is! FunctionExpression) return;
    final params = generator.parameters?.parameters;
    if (params == null || params.length != 1) return;
    final index = params.first.name?.lexeme;
    if (index == null || index == 'context') return;

    final body = utils.getNodeText(generator.body);
    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleInsertion(ctor.type.end, '.builder');
      builder.addSimpleReplacement(
        range.node(children),
        'itemCount: ${utils.getNodeText(count)}, '
        'itemBuilder: (context, $index) $body',
      );
    });
  }
}
