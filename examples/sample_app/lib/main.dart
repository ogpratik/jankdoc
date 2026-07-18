import 'package:flutter/material.dart';
import 'package:jankdoc/jankdoc.dart';

import 'screens/animated_builder_storm_screen.dart';
import 'screens/opacity_overdraw_screen.dart';
import 'screens/setstate_in_build_screen.dart';

Future<void> main() async {
  // Attach JankDoc BEFORE runApp. This starts the analysis daemon and begins
  // collecting frame timing. In release mode this is a compile-time no-op.
  await JankDoc.attach();
  runApp(const SampleApp());
}

class SampleApp extends StatelessWidget {
  const SampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'JankDoc Sample',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
          useMaterial3: true,
        ),
        home: const _HomePage(),
      );
}

class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('JankDoc Sample App')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            _IntroCard(),
            SizedBox(height: 16),
            _JankTile(
              title: 'A · AnimatedBuilder rebuild storm',
              subtitle: 'Expected diagnosis: animated-builder-rebuild-storm',
              colour: Colors.redAccent,
              screen: AnimatedBuilderStormScreen(),
            ),
            _JankTile(
              title: 'B · setState inside build()',
              subtitle: 'Expected diagnosis: setstate-in-build',
              colour: Colors.deepPurple,
              screen: SetStateInBuildScreen(),
            ),
            _JankTile(
              title: 'C · Opacity raster overdraw',
              subtitle: 'Expected diagnosis: raster-overdraw-opacity',
              colour: Colors.teal,
              screen: OpacityOverdrawScreen(),
            ),
          ],
        ),
      );
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tap a screen to trigger jank.',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              SizedBox(height: 6),
              Text(
                'Open Flutter DevTools → JankDoc tab. Each screen intentionally '
                'triggers a specific antipattern that JankDoc should diagnose.',
              ),
            ],
          ),
        ),
      );
}

class _JankTile extends StatelessWidget {
  const _JankTile({
    required this.title,
    required this.subtitle,
    required this.colour,
    required this.screen,
  });

  final String title;
  final String subtitle;
  final Color colour;
  final Widget screen;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(backgroundColor: colour, radius: 8),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => screen),
          ),
        ),
      );
}
