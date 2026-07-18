import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/daemon_provider.dart';
import '../services/daemon_client.dart';

/// Shown in the diagnosis list and detail panel when there are no diagnoses.
///
/// Displays different copy depending on whether the daemon is connected.
class EmptyState extends ConsumerWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionStateProvider).valueOrNull ??
        DaemonConnectionState.disconnected;
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                _icon(state),
                key: ValueKey(state),
                size: 40,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _headline(state),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _body(state),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (state == DaemonConnectionState.disconnected) ...[
              const SizedBox(height: 20),
              _CodeSnippet(theme),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _icon(DaemonConnectionState s) => switch (s) {
        DaemonConnectionState.connected => Icons.check_circle_outline,
        DaemonConnectionState.connecting => Icons.sync_outlined,
        DaemonConnectionState.disconnected => Icons.speed_outlined,
      };

  static String _headline(DaemonConnectionState s) => switch (s) {
        DaemonConnectionState.connected => 'No jank detected yet',
        DaemonConnectionState.connecting => 'Connecting to daemon…',
        DaemonConnectionState.disconnected => 'JankDoc not attached',
      };

  static String _body(DaemonConnectionState s) => switch (s) {
        DaemonConnectionState.connected =>
          'JankDoc is watching your frames.\nDiagnoses appear here the moment jank is detected.',
        DaemonConnectionState.connecting =>
          'Found ext.jankdoc.daemonUrl — establishing HTTP connection.',
        DaemonConnectionState.disconnected =>
          'Add one line to your app\'s main() to start\nreal-time jank diagnosis.',
      };
}

class _CodeSnippet extends StatelessWidget {
  const _CodeSnippet(this.theme);
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'void main() async {',
            style: _codeStyle(theme),
          ),
          Row(
            children: [
              Text('  await ', style: _codeStyle(theme)),
              Text(
                'JankDoc',
                style: _codeStyle(theme).copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text('.attach();', style: _codeStyle(theme)),
            ],
          ),
          Text(
            '  runApp(const MyApp());',
            style: _codeStyle(theme),
          ),
          Text('}', style: _codeStyle(theme)),
        ],
      ),
    );
  }

  static TextStyle _codeStyle(ThemeData t) => TextStyle(
        fontSize: 12,
        fontFamily: 'monospace',
        color: t.colorScheme.onSurface.withValues(alpha: 0.75),
        height: 1.6,
      );
}
