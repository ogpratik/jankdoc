// Every widget here contains exactly one JankDoc antipattern. The trailing
// `// expect: <rule>` comment names the diagnostic `dart analyze` must
// report on that line (checked by packages/jankdoc_lints/tool/check_demo.dart).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class SetStateLoop extends StatefulWidget {
  const SetStateLoop({super.key});

  @override
  State<SetStateLoop> createState() => _SetStateLoopState();
}

class _SetStateLoopState extends State<SetStateLoop> {
  int _frames = 0;

  @override
  Widget build(BuildContext context) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _frames++); // expect: setstate_in_build
    });
    return Text('$_frames');
  }
}

class ConfigLabel extends StatelessWidget {
  const ConfigLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final raw = File('config.json').readAsStringSync(); // expect: sync_io_in_build
    final config = jsonDecode(raw) as Map<String, Object?>; // expect: json_decode_in_build
    return Text('${config['title']}');
  }
}

class Pulse extends StatelessWidget {
  const Pulse({super.key, required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        builder: (context, _) => Opacity( // expect: animated_opacity_widget
          opacity: animation.value,
          child: const FlutterLogo(),
        ),
      );
}

class SpinningList extends StatelessWidget {
  const SpinningList({super.key, required this.spin});

  final Animation<double> spin;

  @override
  Widget build(BuildContext context) => ListView.builder(
        itemCount: 500,
        itemBuilder: (context, i) => AnimatedBuilder( // expect: animated_builder_per_item
          animation: spin,
          builder: (context, _) => Transform.rotate(
            angle: spin.value * 6.28,
            child: Text('Item $i'),
          ),
        ),
      );
}

class RoundedCard extends StatelessWidget {
  const RoundedCard({super.key});

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAliasWithSaveLayer, // expect: clip_save_layer
        child: const SizedBox(height: 80),
      );
}

class Contacts extends StatelessWidget {
  const Contacts({super.key});

  @override
  Widget build(BuildContext context) => ListView( // expect: non_lazy_list
        children: List.generate(1000, (i) => ListTile(title: Text('Contact $i'))),
      );
}
