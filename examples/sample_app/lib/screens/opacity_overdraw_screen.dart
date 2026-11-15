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
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 10,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: 600,
            // Bad: every Opacity forces a saveLayer for its subtree on every
            // frame; nested and repeated across the grid they saturate the
            // raster thread.
            itemBuilder: (context, index) {
              final fade = (_controller.value + (index * 0.02)) % 1.0;
              return Opacity(
                opacity: fade,
                child: Opacity(
                  opacity: 1.0 - fade / 2,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.primaries[index % Colors.primaries.length],
                        Colors.primaries[(index + 5) % Colors.primaries.length],
                      ]),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Opacity(
                      opacity: fade,
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
              );
            },
          ),
        ),
      );
}
