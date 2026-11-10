/// JankDoc's analyzer plugin: flags jank-causing Flutter code as you type.
///
/// Enable it in the root `analysis_options.yaml`:
///
/// ```yaml
/// plugins:
///   jankdoc_lints: ^1.0.0-beta.1
/// ```
///
/// Diagnostics then appear in the IDE (with quick fixes) and in
/// `dart analyze` / `flutter analyze` — which is also what AI coding agents
/// run, so they see and fix the same problems.
library;

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/fixes/fixes.dart';
import 'src/rules/animated_builder_per_item.dart';
import 'src/rules/animated_opacity_widget.dart';
import 'src/rules/clip_save_layer.dart';
import 'src/rules/json_decode_in_build.dart';
import 'src/rules/non_lazy_list.dart';
import 'src/rules/setstate_in_build.dart';
import 'src/rules/sync_io_in_build.dart';

final plugin = JankDocPlugin();

class JankDocPlugin extends Plugin {
  @override
  String get name => 'jankdoc_lints';

  @override
  void register(PluginRegistry registry) {
    // Warning rules: on by default; disable per rule under
    // `plugins: jankdoc_lints: diagnostics:` in analysis_options.yaml.
    registry
      ..registerWarningRule(SetStateInBuild())
      ..registerWarningRule(SyncIoInBuild())
      ..registerWarningRule(JsonDecodeInBuild())
      ..registerWarningRule(AnimatedOpacityWidget())
      ..registerWarningRule(AnimatedBuilderPerItem())
      ..registerWarningRule(ClipSaveLayer())
      ..registerWarningRule(NonLazyList())
      ..registerFixForRule(ClipSaveLayer.code, UseClipAntiAlias.new)
      ..registerFixForRule(AnimatedOpacityWidget.code, UseFadeTransition.new)
      ..registerFixForRule(NonLazyList.code, UseListViewBuilder.new);
  }
}
