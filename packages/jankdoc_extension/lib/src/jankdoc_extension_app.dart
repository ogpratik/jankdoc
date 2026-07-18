import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/daemon_provider.dart';
import 'providers/diagnosis_provider.dart';
import 'widgets/detail_panel.dart';
import 'widgets/diagnosis_list_panel.dart';
import 'widgets/status_indicator.dart';

/// Root widget for the JankDoc DevTools extension.
///
/// Layout:
/// ┌────────────────────────────────────────────────────────────────┐
/// │  StatusIndicator  (36px — connection · model · counts)         │
/// ├──────────────────────┬─────────────────────────────────────────┤
/// │  DiagnosisListPanel  │  DetailPanel                            │
/// │  (300px fixed)       │  (fills remaining width)                │
/// └──────────────────────┴─────────────────────────────────────────┘
///
/// The split can be dragged to resize. Below ~800px the layout collapses
/// to a navigator-style single column.
class JankDocExtensionApp extends ConsumerStatefulWidget {
  const JankDocExtensionApp({super.key});

  @override
  ConsumerState<JankDocExtensionApp> createState() =>
      _JankDocExtensionAppState();
}

class _JankDocExtensionAppState extends ConsumerState<JankDocExtensionApp> {
  static const _minListWidth = 220.0;
  static const _maxListWidth = 520.0;
  static const _defaultListWidth = 300.0;
  static const _collapseThreshold = 700.0;

  double _listWidth = _defaultListWidth;

  @override
  Widget build(BuildContext context) {
    // Subscribe to the diagnosis stream eagerly — this drives live updates
    // even when no widget is directly listening to the stream itself.
    ref.watch(diagnosisStreamProvider);

    final totalWidth = MediaQuery.sizeOf(context).width;
    final collapsed = totalWidth < _collapseThreshold;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          const StatusIndicator(),
          const _DaemonUnreachableBanner(),
          Expanded(
            child: collapsed
                ? _CollapsedLayout()
                : _SplitLayout(
                    listWidth: _listWidth,
                    onResize: (delta) {
                      setState(() {
                        _listWidth = (_listWidth + delta).clamp(
                          _minListWidth,
                          _maxListWidth,
                        );
                      });
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Daemon-unreachable banner ─────────────────────────────────────────────────

/// Shown after 30 s of failed /health checks — tells the user exactly what
/// to fix rather than leaving them with a spinning amber dot.
class _DaemonUnreachableBanner extends ConsumerWidget {
  const _DaemonUnreachableBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timedOut = ref.watch(daemonTimedOutProvider).valueOrNull ?? false;
    if (!timedOut) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      color: isDark ? const Color(0xFF3E2723) : const Color(0xFFFFF3E0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: Color(0xFFE65100),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Daemon not reachable. '
              "Did you call JankDoc.attach() before runApp()?",
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? const Color(0xFFFFCCBC)
                    : const Color(0xFF4E2600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Split layout ──────────────────────────────────────────────────────────────

class _SplitLayout extends StatelessWidget {
  const _SplitLayout({
    required this.listWidth,
    required this.onResize,
  });

  final double listWidth;
  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? const Color(0xFF333333)
        : const Color(0xFFE0E0E0);

    return Row(
      children: [
        SizedBox(
          width: listWidth,
          child: const DiagnosisListPanel(),
        ),
        // ── Draggable divider ─────────────────────────────────────────────
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            onHorizontalDragUpdate: (d) => onResize(d.delta.dx),
            child: Container(
              width: 4,
              color: Colors.transparent,
              child: Center(
                child: Container(
                  width: 1,
                  color: dividerColor,
                ),
              ),
            ),
          ),
        ),
        const Expanded(child: DetailPanel()),
      ],
    );
  }
}

// ── Collapsed layout (narrow viewports) ──────────────────────────────────────

/// On narrow screens (e.g. small DevTools window), show a bottom-sheet
/// style overlay for the detail panel instead of a side-by-side split.
class _CollapsedLayout extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedDiagnosisProvider);

    return Stack(
      children: [
        const DiagnosisListPanel(),
        if (selected != null)
          GestureDetector(
            onTap: () =>
                ref.read(selectedDiagnosisProvider.notifier).state = null,
            child: Container(color: Colors.black45),
          ),
        if (selected != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: Material(
              elevation: 8,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                children: [
                  // Drag handle + close
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => ref
                              .read(selectedDiagnosisProvider.notifier)
                              .state = null,
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Expanded(child: DetailPanel()),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
