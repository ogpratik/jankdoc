// `explain_pattern`: the JankDoc KB explanation for a rule, plus a
// before/after fix. The KB text is generated from the runtime catalog
// (kb_data.dart); the code samples mirror examples/lint_demo/lib/{bad,good}.dart,
// which CI checks against the real analyzer.
import 'findings.dart';
import 'kb_data.dart';

const _fixes = <String, (String, String)>{
  'setstate_in_build': (
    '''
@override
Widget build(BuildContext context) {
  // Every frame schedules another setState → another build.
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (mounted) setState(() => _frames++);
  });
  return Text('\$_frames');
}''',
    '''
// Change state in response to events (or in initState), never from build.
@override
Widget build(BuildContext context) => ElevatedButton(
      onPressed: () => setState(() => _taps++),
      child: Text('\$_taps'),
    );''',
  ),
  'sync_io_in_build': (
    '''
@override
Widget build(BuildContext context) {
  final raw = File('config.json').readAsStringSync(); // blocks the UI thread
  return Text(raw);
}''',
    '''
// Load once, asynchronously; build() only reads the cached future.
late final Future<String> _raw = File('config.json').readAsString();

@override
Widget build(BuildContext context) => FutureBuilder(
      future: _raw,
      builder: (context, snapshot) => Text(snapshot.data ?? ''),
    );''',
  ),
  'json_decode_in_build': (
    '''
@override
Widget build(BuildContext context) {
  final config = jsonDecode(raw) as Map<String, Object?>; // every rebuild
  return Text('\${config['title']}');
}''',
    '''
// Decode once, off the UI isolate.
late final Future<Map<String, Object?>> _config =
    compute((String s) => jsonDecode(s) as Map<String, Object?>, raw);

@override
Widget build(BuildContext context) => FutureBuilder(
      future: _config,
      builder: (context, snapshot) => Text('\${snapshot.data?['title']}'),
    );''',
  ),
  'animated_opacity_widget': (
    '''
AnimatedBuilder(
  animation: animation,
  builder: (context, _) => Opacity( // rebuild + saveLayer every frame
    opacity: animation.value,
    child: const FlutterLogo(),
  ),
)''',
    '''
// Animates on the compositor; nothing rebuilds.
FadeTransition(opacity: animation, child: const FlutterLogo())''',
  ),
  'animated_builder_per_item': (
    '''
ListView.builder(
  itemCount: 500,
  itemBuilder: (context, i) => AnimatedBuilder( // one per item
    animation: spin,
    builder: (context, _) => Transform.rotate(
      angle: spin.value * 6.28,
      child: Text('Item \$i'),
    ),
  ),
)''',
    '''
// A transition widget repaints only the animated part.
ListView.builder(
  itemCount: 500,
  itemBuilder: (context, i) =>
      RotationTransition(turns: spin, child: Text('Item \$i')),
)''',
  ),
  'clip_save_layer': (
    '''
Card(
  clipBehavior: Clip.antiAliasWithSaveLayer, // offscreen layer per paint
  child: const SizedBox(height: 80),
)''',
    '''
const Card(
  clipBehavior: Clip.antiAlias,
  child: SizedBox(height: 80),
)''',
  ),
  'non_lazy_list': (
    '''
ListView( // builds all 1000 tiles up front
  children: List.generate(1000, (i) => ListTile(title: Text('Contact \$i'))),
)''',
    '''
ListView.builder( // builds only what is on screen
  itemCount: 1000,
  itemBuilder: (context, i) => ListTile(title: Text('Contact \$i')),
)''',
  ),
};

/// Every id `explain_pattern` accepts: rule names and KB pattern ids.
List<String> get knownPatternIds => [
  for (final e in jankdocRules.entries) ...[e.key, e.value],
];

/// The explanation for [id] — a rule name (`non_lazy_list`, optionally
/// prefixed `jankdoc_lints/`) or a KB pattern id (`listview-non-lazy`) — or
/// null if unknown.
Map<String, Object?>? explainPattern(String id) {
  final key = id.trim().toLowerCase().replaceFirst('jankdoc_lints/', '');
  final rule = jankdocRules.containsKey(key)
      ? key
      : jankdocRules.entries
            .where((e) => e.value == key)
            .map((e) => e.key)
            .firstOrNull;
  if (rule == null) return null;
  final patternId = jankdocRules[rule]!;
  final kb = kbEntries[patternId]!;
  final (before, after) = _fixes[rule]!;
  return {
    'rule': 'jankdoc_lints/$rule',
    'pattern': patternId,
    'title': kb['title'],
    'severity': kb['severity'],
    'explanation': kb['description'],
    'fix': {
      'summary': kb['fixGuidance'],
      'before': before,
      'after': after,
      'expectedImprovement': kb['expectedImprovement'],
    },
    'sources': kb['sources'],
  };
}

/// Markdown rendering of an [explainPattern] result.
String explainPatternText(Map<String, Object?> e) {
  final fix = e['fix'] as Map<String, Object?>;
  return '''
# ${e['title']} (`${e['pattern']}`, rule `${e['rule']}`)

Severity: ${e['severity']}

${e['explanation']}

## Fix

${fix['summary']}

Before:
```dart
${fix['before']}
```

After:
```dart
${fix['after']}
```

Expected improvement: ${fix['expectedImprovement']}

Sources:
${(e['sources'] as List).map((s) => '- $s').join('\n')}
''';
}
