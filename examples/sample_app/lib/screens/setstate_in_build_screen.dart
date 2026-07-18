import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Screen B — `setState` inside `build()`.
///
/// The build method schedules another `setState` on the next frame, guaranteeing
/// perpetual rebuilds and pegging the UI thread.
///
/// **Expected diagnosis**: `setstate-in-build`
///
/// **The fix** is to lift state changes out of `build()` — into `initState`,
/// event handlers, or `didChangeDependencies`. Never call `setState` from
/// `build()`; it produces an unbounded rebuild loop.
class SetStateInBuildScreen extends StatefulWidget {
  const SetStateInBuildScreen({super.key});

  @override
  State<SetStateInBuildScreen> createState() => _SetStateInBuildScreenState();
}

class _SetStateInBuildScreenState extends State<SetStateInBuildScreen> {
  int _counter = 0;

  @override
  Widget build(BuildContext context) {
    // Bad: scheduling setState from within build() creates an infinite rebuild
    // loop that saturates the UI thread every frame.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _counter++;
        });
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('B · setState in build()')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Rebuild counter',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(
              '$_counter',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'This screen intentionally calls setState() from build().',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
