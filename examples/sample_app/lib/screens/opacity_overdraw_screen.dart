import 'package:flutter/material.dart';

/// Screen C — `Opacity` raster overdraw.
///
/// A grid of `Opacity` widgets animating from 0 → 1 → 0 every frame. Because
/// `Opacity` triggers a `saveLayer` on the raster thread for each subtree,
/// this creates severe raster-thread jank without much UI-thread cost.
///
/// **Expected diagnosis**: `raster-overdraw-opacity`
///
/// **The fix** is to swap `Opacity` for `AnimatedOpacity` on a leaf widget, or
/// (better) use `FadeTransition` which the compositor can offload to the GPU
/// without a saveLayer.
class OpacityOverdrawScreen extends StatefulWidget {
  const OpacityOverdrawScreen({super.key});

  @override
  State<OpacityOverdrawScreen> createState() => _OpacityOverdrawScreenState();
}

class _OpacityOverdrawScreenState extends State<OpacityOverdrawScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('C · Opacity overdraw')),
        body: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: 60,
            // Bad: Opacity forces a saveLayer for each subtree every frame,
            // saturating the raster thread.
            itemBuilder: (context, index) => Opacity(
              opacity: (_controller.value + (index * 0.02)) % 1.0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.primaries[index % Colors.primaries.length],
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
