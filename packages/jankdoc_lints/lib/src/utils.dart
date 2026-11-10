import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Whether [element] is declared in a library whose URI starts with [prefix]
/// (e.g. `package:flutter/`, `dart:io`).
bool isFrom(Element? element, String prefix) =>
    element?.library?.uri.toString().startsWith(prefix) ?? false;

/// Whether [type] is (or extends/implements) the Flutter class [className].
bool isFlutterType(DartType? type, String className) {
  if (type is! InterfaceType) return false;
  bool matches(InterfaceType t) =>
      t.element.name == className && isFrom(t.element, 'package:flutter/');
  return matches(type) || type.element.allSupertypes.any(matches);
}

/// The Flutter class constructed by [node], if it is one of [classNames].
String? constructedFlutterClass(
  InstanceCreationExpression node,
  Set<String> classNames,
) {
  final element = node.constructorName.type.element;
  if (element is! InterfaceElement) return null;
  final name = element.name;
  if (name == null || !classNames.contains(name)) return null;
  return isFrom(element, 'package:flutter/') ? name : null;
}

/// The named argument [name] of [arguments], or null.
NamedArgument? namedArgument(ArgumentList arguments, String name) {
  for (final arg in arguments.arguments) {
    if (arg is NamedArgument && arg.name.lexeme == name) return arg;
  }
  return null;
}

/// How a closure between a node and its enclosing `build` method is called.
enum ClosureRole {
  /// Runs during build/layout: `itemBuilder:`, `builder:`, `.map(...)` …
  buildTime,

  /// Scheduled from build to run right after it: `addPostFrameCallback`,
  /// `Future.microtask`, `scheduleMicrotask`, `Timer` …
  scheduledFromBuild,

  /// Runs on user input (`onPressed:`, `onTap:` …) — not per frame.
  eventHandler,

  /// Moved off the UI isolate (`compute`, `Isolate.run`) — this is the fix.
  offMainIsolate,
}

const _schedulingMethods = {
  'addPostFrameCallback',
  'scheduleFrameCallback',
  'addPersistentFrameCallback',
  'scheduleMicrotask',
  'microtask',
  'delayed',
  'then',
  'run',
};

ClosureRole _roleOf(FunctionExpression closure) {
  var parent = closure.parent;
  if (parent is NamedArgument) {
    final label = parent.name.lexeme;
    if (RegExp(r'^on[A-Z]').hasMatch(label)) return ClosureRole.eventHandler;
    parent = parent.parent;
  }
  final invocation = parent?.parent;
  if (parent is ArgumentList) {
    if (invocation is MethodInvocation) {
      final name = invocation.methodName.name;
      final target = invocation.target;
      final isIsolateRun =
          name == 'run' &&
          target is SimpleIdentifier &&
          target.name == 'Isolate';
      if (name == 'compute' || isIsolateRun) return ClosureRole.offMainIsolate;
      if (_schedulingMethods.contains(name)) {
        return ClosureRole.scheduledFromBuild;
      }
    }
    if (invocation is InstanceCreationExpression) {
      final typeName = invocation.constructorName.type.name.lexeme;
      if (typeName == 'Future' || typeName == 'Timer') {
        return ClosureRole.scheduledFromBuild;
      }
    }
  }
  return ClosureRole.buildTime;
}

/// The `build(BuildContext)` method [node] runs in, walking out through
/// closures whose role is in [through]. Returns null when [node] is not in a
/// build method, or is inside a closure with any other role.
MethodDeclaration? enclosingBuild(
  AstNode node, {
  Set<ClosureRole> through = const {ClosureRole.buildTime},
}) {
  for (AstNode? n = node.parent; n != null; n = n.parent) {
    if (n is FunctionExpression) {
      if (!through.contains(_roleOf(n))) return null;
    } else if (n is MethodDeclaration) {
      return _isBuildMethod(n) ? n : null;
    } else if (n is FunctionDeclaration || n is ClassDeclaration) {
      return null;
    }
  }
  return null;
}

bool _isBuildMethod(MethodDeclaration method) {
  if (method.name.lexeme != 'build') return false;
  final params = method.parameters?.parameters;
  if (params == null || params.isEmpty) return false;
  final type = params.first.declaredFragment?.element.type;
  return isFlutterType(type, 'BuildContext');
}

/// Whether [e] is `List.generate(...)`. Resolved code sees it as a constructor
/// call; unresolved or prefixed code may still parse it as a method call.
bool isListGenerate(Expression e) {
  if (e is InstanceCreationExpression) {
    return e.constructorName.type.name.lexeme == 'List' &&
        e.constructorName.name?.name == 'generate';
  }
  if (e is MethodInvocation && e.methodName.name == 'generate') {
    final target = e.target;
    return target is SimpleIdentifier && target.name == 'List';
  }
  return false;
}

/// The arguments of a `List.generate(...)` expression, if [e] is one.
ArgumentList? listGenerateArguments(Expression e) => !isListGenerate(e)
    ? null
    : switch (e) {
        InstanceCreationExpression() => e.argumentList,
        MethodInvocation() => e.argumentList,
        _ => null,
      };

/// Whether [expression] reads `.value` from a Flutter `Animation`.
bool readsAnimationValue(Expression expression) {
  final finder = _AnimationValueFinder();
  expression.accept(finder);
  return finder.found;
}

/// If [expression] is exactly `<animation>.value`, the `<animation>` part.
Expression? animationOfValueRead(Expression expression) {
  final e = expression.unParenthesized;
  if (e is PrefixedIdentifier &&
      e.identifier.name == 'value' &&
      isFlutterType(e.prefix.staticType, 'Animation')) {
    return e.prefix;
  }
  if (e is PropertyAccess &&
      e.propertyName.name == 'value' &&
      isFlutterType(e.realTarget.staticType, 'Animation')) {
    return e.realTarget;
  }
  return null;
}

class _AnimationValueFinder extends UnifyingAstVisitor<void> {
  bool found = false;

  @override
  void visitNode(AstNode node) {
    if (found) return;
    if (node is Expression && animationOfValueRead(node) != null) {
      found = true;
      return;
    }
    node.visitChildren(this);
  }
}
