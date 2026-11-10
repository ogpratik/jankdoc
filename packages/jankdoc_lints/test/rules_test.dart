import 'package:jankdoc_lints/src/rules/animated_builder_per_item.dart';
import 'package:jankdoc_lints/src/rules/animated_opacity_widget.dart';
import 'package:jankdoc_lints/src/rules/clip_save_layer.dart';
import 'package:jankdoc_lints/src/rules/non_lazy_list.dart';
import 'package:jankdoc_lints/src/rules/setstate_in_build.dart';
import 'package:jankdoc_lints/src/rules/sync_io_in_build.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'flutter_stub.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(SetStateInBuildTest);
    defineReflectiveTests(SyncIoInBuildTest);
    defineReflectiveTests(AnimatedOpacityWidgetTest);
    defineReflectiveTests(AnimatedBuilderPerItemTest);
    defineReflectiveTests(ClipSaveLayerTest);
    defineReflectiveTests(NonLazyListTest);
  });
}

const _state = r'''
import 'package:flutter/widgets.dart';

class W extends StatefulWidget {
  @override
  State<W> createState() => _S();
}
''';

@reflectiveTest
class SetStateInBuildTest extends FlutterRuleTest {
  @override
  void setUp() {
    rule = SetStateInBuild();
    super.setUp();
  }

  Future<void> test_direct() async {
    const code = '''$_state
class _S extends State<W> {
  int n = 0;
  @override
  Widget build(BuildContext context) {
    setState(() => n++);
    return const Text('');
  }
}
''';
    await assertDiagnostics(code, [lintOn(code, 'setState')]);
  }

  Future<void> test_postFrameCallback() async {
    const code = '''$_state
class _S extends State<W> {
  int n = 0;
  @override
  Widget build(BuildContext context) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => n++);
    });
    return const Text('');
  }
}
''';
    await assertDiagnostics(code, [lintOn(code, 'setState')]);
  }

  Future<void> test_microtask() async {
    const code = '''$_state
class _S extends State<W> {
  int n = 0;
  @override
  Widget build(BuildContext context) {
    Future.microtask(() => setState(() => n++));
    return const Text('');
  }
}
''';
    await assertDiagnostics(code, [lintOn(code, 'setState')]);
  }

  Future<void> test_eventHandler_ok() async {
    await assertNoDiagnostics('''$_state
class _S extends State<W> {
  int n = 0;
  @override
  Widget build(BuildContext context) =>
      ElevatedButton(onPressed: () => setState(() => n++));
}
''');
  }

  Future<void> test_initState_ok() async {
    await assertNoDiagnostics('''$_state
class _S extends State<W> {
  int n = 0;
  @override
  void initState() {
    super.initState();
    setState(() => n++);
  }
  @override
  Widget build(BuildContext context) => const Text('');
}
''');
  }
}

@reflectiveTest
class SyncIoInBuildTest extends FlutterRuleTest {
  @override
  void setUp() {
    rule = SyncIoInBuild();
    super.setUp();
  }

  Future<void> test_readAsStringSync() async {
    const code =
        '''
import 'dart:io';
import 'package:flutter/widgets.dart';

class W extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Text('\${File('a.txt').lastModifiedSync()}');
}
''';
    await assertDiagnostics(code, [lintOn(code, 'lastModifiedSync')]);
  }

  Future<void> test_inItemBuilder() async {
    const code = '''
import 'dart:io';
import 'package:flutter/widgets.dart';

class W extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView.builder(
        itemBuilder: (context, i) => Text('\${File('a').existsSync()}'),
      );
}
''';
    await assertDiagnostics(code, [lintOn(code, 'existsSync')]);
  }

  Future<void> test_eventHandler_ok() async {
    await assertNoDiagnostics('''
import 'dart:io';
import 'package:flutter/widgets.dart';

class W extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      ElevatedButton(onPressed: () => File('a').existsSync());
}
''');
  }

  Future<void> test_outsideBuild_ok() async {
    await assertNoDiagnostics('''
import 'dart:io';

bool load() => File('a.txt').existsSync();
''');
  }
}

@reflectiveTest
class AnimatedOpacityWidgetTest extends FlutterRuleTest {
  @override
  void setUp() {
    rule = AnimatedOpacityWidget();
    super.setUp();
  }

  Future<void> test_animationValue() async {
    const code = '''
import 'package:flutter/widgets.dart';

Widget f(AnimationController c) => Opacity(opacity: c.value);
''';
    await assertDiagnostics(code, [lintOn(code, 'Opacity')]);
  }

  Future<void> test_computedFromAnimation() async {
    const code = '''
import 'package:flutter/widgets.dart';

Widget f(Animation<double> a, int i) =>
    Opacity(opacity: (a.value + i * 0.02) % 1.0);
''';
    await assertDiagnostics(code, [lintOn(code, 'Opacity')]);
  }

  Future<void> test_constantOpacity_ok() async {
    await assertNoDiagnostics('''
import 'package:flutter/widgets.dart';

Widget f() => const Opacity(opacity: 0.5);
''');
  }
}

@reflectiveTest
class AnimatedBuilderPerItemTest extends FlutterRuleTest {
  @override
  void setUp() {
    rule = AnimatedBuilderPerItem();
    super.setUp();
  }

  Future<void> test_perItem() async {
    const code = '''
import 'package:flutter/widgets.dart';

Widget f(AnimationController c) => ListView.builder(
      itemBuilder: (context, i) => AnimatedBuilder(
        animation: c,
        builder: (context, _) => Text('\$i'),
      ),
    );
''';
    await assertDiagnostics(code, [lintOn(code, 'AnimatedBuilder')]);
  }

  Future<void> test_hoisted_ok() async {
    await assertNoDiagnostics('''
import 'package:flutter/widgets.dart';

Widget f(AnimationController c) => AnimatedBuilder(
      animation: c,
      builder: (context, _) => ListView.builder(
        itemBuilder: (context, i) => Text('\$i'),
      ),
    );
''');
  }

  Future<void> test_withChild_ok() async {
    await assertNoDiagnostics('''
import 'package:flutter/widgets.dart';

Widget f(AnimationController c) => ListView.builder(
      itemBuilder: (context, i) => AnimatedBuilder(
        animation: c,
        child: Text('\$i'),
        builder: (context, child) => child!,
      ),
    );
''');
  }
}

@reflectiveTest
class ClipSaveLayerTest extends FlutterRuleTest {
  @override
  void setUp() {
    rule = ClipSaveLayer();
    super.setUp();
  }

  Future<void> test_saveLayer() async {
    const code = '''
import 'package:flutter/widgets.dart';

Widget f() => Container(clipBehavior: Clip.antiAliasWithSaveLayer);
''';
    await assertDiagnostics(code, [lintOn(code, 'antiAliasWithSaveLayer')]);
  }

  Future<void> test_antiAlias_ok() async {
    await assertNoDiagnostics('''
import 'package:flutter/widgets.dart';

Widget f() => Container(clipBehavior: Clip.antiAlias);
''');
  }
}

@reflectiveTest
class NonLazyListTest extends FlutterRuleTest {
  @override
  void setUp() {
    rule = NonLazyList();
    super.setUp();
  }

  Future<void> test_listGenerate() async {
    const code = '''
import 'package:flutter/widgets.dart';

Widget f() => ListView(children: List.generate(100, (i) => Text('\$i')));
''';
    await assertDiagnostics(code, [lintOn(code, 'ListView')]);
  }

  Future<void> test_mapToList() async {
    const code = '''
import 'package:flutter/widgets.dart';

Widget f(List<String> items) =>
    ListView(children: items.map((s) => Text(s)).toList());
''';
    await assertDiagnostics(code, [lintOn(code, 'ListView')]);
  }

  Future<void> test_collectionFor() async {
    const code = '''
import 'package:flutter/widgets.dart';

Widget f(List<String> items) =>
    GridView.count(crossAxisCount: 2, children: [for (final s in items) Text(s)]);
''';
    await assertDiagnostics(code, [lintOn(code, 'GridView.count')]);
  }

  Future<void> test_literalChildren_ok() async {
    await assertNoDiagnostics('''
import 'package:flutter/widgets.dart';

Widget f() => ListView(children: const [Text('a'), Text('b')]);
''');
  }

  Future<void> test_builder_ok() async {
    await assertNoDiagnostics('''
import 'package:flutter/widgets.dart';

Widget f() => ListView.builder(itemBuilder: (context, i) => Text('\$i'));
''');
  }
}
