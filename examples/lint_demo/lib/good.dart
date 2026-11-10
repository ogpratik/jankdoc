// The fixed counterparts of bad.dart. `flutter analyze` must report no
// JankDoc diagnostics in this file.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: () => setState(() => _taps++),
        child: Text('$_taps'),
      );
}

class ConfigLabel extends StatefulWidget {
  const ConfigLabel({super.key});

  @override
  State<ConfigLabel> createState() => _ConfigLabelState();
}

class _ConfigLabelState extends State<ConfigLabel> {
  late final Future<Map<String, Object?>> _config = _load();

  static Future<Map<String, Object?>> _load() async {
    final raw = await File('config.json').readAsString();
    return compute((String s) => jsonDecode(s) as Map<String, Object?>, raw);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _config,
        builder: (context, snapshot) => Text('${snapshot.data?['title']}'),
      );
}

class Pulse extends StatelessWidget {
  const Pulse({super.key, required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: animation, child: const FlutterLogo());
}

class SpinningList extends StatelessWidget {
  const SpinningList({super.key, required this.spin});

  final Animation<double> spin;

  @override
  Widget build(BuildContext context) => ListView.builder(
        itemCount: 500,
        itemBuilder: (context, i) =>
            RotationTransition(turns: spin, child: Text('Item $i')),
      );
}

class RoundedCard extends StatelessWidget {
  const RoundedCard({super.key});

  @override
  Widget build(BuildContext context) => const Card(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(height: 80),
      );
}

class Contacts extends StatelessWidget {
  const Contacts({super.key});

  @override
  Widget build(BuildContext context) => ListView.builder(
        itemCount: 1000,
        itemBuilder: (context, i) => ListTile(title: Text('Contact $i')),
      );
}
