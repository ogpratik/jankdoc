import 'package:flutter/material.dart';

/// Screen A — AnimatedBuilder rebuild storm.
///
/// Wraps every list item in an `AnimatedBuilder` bound to a global controller.
/// Every tick, all visible items rebuild — producing a rebuild storm that
/// dominates the UI thread.
///
/// **Expected diagnosis**: `animated-builder-rebuild-storm`
///
/// **The fix** would be to hoist the `AnimatedBuilder` above the list and let
/// each item receive the animation value as a parameter, so only the animated
/// property rebuilds — not every list item.
class AnimatedBuilderStormScreen extends StatefulWidget {
  const AnimatedBuilderStormScreen({super.key});

  @override
  State<AnimatedBuilderStormScreen> createState() =>
      _AnimatedBuilderStormScreenState();
}

class _AnimatedBuilderStormScreenState extends State<AnimatedBuilderStormScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('A · AnimatedBuilder storm')),
        body: ListView.builder(
          itemCount: 200,
          // Bad: an AnimatedBuilder per list item rebuilds every tick.
          itemBuilder: (context, index) => AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final angle = _controller.value * 6.28;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Transform.rotate(
                      angle: angle,
                      child: const Icon(Icons.autorenew, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Item #$index')),
                    Text('${(_controller.value * 100).toStringAsFixed(0)}%'),
                  ],
                ),
              );
            },
          ),
        ),
      );
}
