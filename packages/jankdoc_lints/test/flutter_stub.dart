import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
// ignore: implementation_imports
import 'package:analyzer_testing/src/analysis_rule/pub_package_resolution.dart'
    show ExpectedDiagnostic;

/// Base for rule tests: adds a minimal `package:flutter` stub and a helper
/// that locates the expected diagnostic by the text it should highlight.
abstract class FlutterRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    newPackage('flutter').addFile('lib/widgets.dart', _flutterStub);
    super.setUp();
  }

  /// Expects a lint on the [occurrence]-th (0-based) [highlight] in [code].
  ExpectedDiagnostic lintOn(
    String code,
    String highlight, {
    int occurrence = 0,
  }) {
    var offset = -1;
    for (var i = 0; i <= occurrence; i++) {
      offset = code.indexOf(highlight, offset + 1);
    }
    if (offset < 0) throw ArgumentError('"$highlight" not found in test code');
    return lint(offset, highlight.length);
  }
}

const _flutterStub = r'''
abstract class BuildContext {}
abstract class Key {}
abstract class Widget {
  const Widget({Key? key});
}
abstract class StatelessWidget extends Widget {
  const StatelessWidget({super.key});
  Widget build(BuildContext context);
}
abstract class StatefulWidget extends Widget {
  const StatefulWidget({super.key});
  State createState();
}
abstract class State<T extends StatefulWidget> {
  bool get mounted => true;
  void initState() {}
  void setState(void Function() fn) {}
  Widget build(BuildContext context);
}
abstract class Listenable {}
abstract class Animation<T> extends Listenable {
  T get value;
}
class AnimationController extends Animation<double> {
  @override
  double get value => 0;
}
class SchedulerBinding {
  static SchedulerBinding get instance => SchedulerBinding();
  void addPostFrameCallback(void Function(Duration) callback) {}
}
enum Clip { none, hardEdge, antiAlias, antiAliasWithSaveLayer }
class Text extends Widget {
  const Text(String data);
}
class Container extends Widget {
  const Container({Clip clipBehavior = Clip.none, Widget? child});
}
class ElevatedButton extends Widget {
  const ElevatedButton({required void Function()? onPressed, Widget? child});
}
class Opacity extends Widget {
  const Opacity({required double opacity, Widget? child});
}
class FadeTransition extends Widget {
  const FadeTransition({required Animation<double> opacity, Widget? child});
}
class AnimatedBuilder extends Widget {
  const AnimatedBuilder({
    required Listenable animation,
    required Widget Function(BuildContext, Widget?) builder,
    Widget? child,
  });
}
class ListenableBuilder extends Widget {
  const ListenableBuilder({
    required Listenable listenable,
    required Widget Function(BuildContext, Widget?) builder,
  });
}
class ListView extends Widget {
  ListView({List<Widget> children = const []});
  ListView.builder({
    required Widget Function(BuildContext, int) itemBuilder,
    int? itemCount,
  });
}
class GridView extends Widget {
  GridView.count({required int crossAxisCount, List<Widget> children = const []});
  GridView.builder({required Widget Function(BuildContext, int) itemBuilder});
}
Future<R> compute<M, R>(R Function(M) callback, M message) => throw 0;
''';
