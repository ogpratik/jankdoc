import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/daemon_provider.dart';
import '../providers/diagnosis_provider.dart';
import '../services/daemon_client.dart';

/// Top-bar status strip: connection state, model name, and live diagnosis count.
class StatusIndicator extends ConsumerWidget {
  const StatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState = ref.watch(connectionStateProvider).valueOrNull ??
        DaemonConnectionState.disconnected;
    final info = ref.watch(daemonInfoProvider).valueOrNull;
    final stats = ref.watch(diagnosisStatsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFF5F5F5),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? const Color(0xFF333333)
                : const Color(0xFFDDDDDD),
          ),
        ),
      ),
      child: Row(
        children: [
          _ConnectionDot(connState),
          const SizedBox(width: 6),
          Text(
            _label(connState),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (info != null) ...[
            _Divider(isDark),
            _Chip(
              icon: Icons.memory_outlined,
              label: info.modelId,
              theme: theme,
            ),
            _Divider(isDark),
            _Chip(
              icon: Icons.link_outlined,
              label: info.ollamaUrl,
              theme: theme,
            ),
          ],
          const Spacer(),
          if (stats.total > 0) ...[
            if (stats.critical > 0)
              _SeverityPill(
                count: stats.critical,
                label: 'critical',
                color: const Color(0xFFE53935),
              ),
            if (stats.high > 0) ...[
              const SizedBox(width: 4),
              _SeverityPill(
                count: stats.high,
                label: 'high',
                color: const Color(0xFFFF6D00),
              ),
            ],
            const SizedBox(width: 8),
            Text(
              '${stats.total} diagnosis${stats.total != 1 ? 'es' : ''}',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
          const SizedBox(width: 4),
          Text(
            'v1.0.0',
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurface.withOpacity(0.35),
            ),
          ),
        ],
      ),
    );
  }

  static String _label(DaemonConnectionState state) => switch (state) {
        DaemonConnectionState.connected => 'JankDoc connected',
        DaemonConnectionState.connecting => 'Connecting to daemon…',
        DaemonConnectionState.disconnected =>
          'Waiting for JankDoc.attach()',
      };
}

// ── Internal helpers ──────────────────────────────────────────────────────────

class _ConnectionDot extends StatefulWidget {
  const _ConnectionDot(this.state);
  final DaemonConnectionState state;

  @override
  State<_ConnectionDot> createState() => _ConnectionDotState();
}

class _ConnectionDotState extends State<_ConnectionDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.state) {
      DaemonConnectionState.connected => const Color(0xFF4CAF50),
      DaemonConnectionState.connecting => const Color(0xFFFFB300),
      DaemonConnectionState.disconnected => const Color(0xFF757575),
    };
    final animate = widget.state == DaemonConnectionState.connecting;

    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) {
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(animate ? _opacity.value : 1.0),
          ),
        );
      },
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider(this.isDark);
  final bool isDark;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 14,
          child: VerticalDivider(
            width: 1,
            color: isDark
                ? const Color(0xFF444444)
                : const Color(0xFFCCCCCC),
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.theme});
  final IconData icon;
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withOpacity(0.7),
              fontFamily: 'monospace',
            ),
          ),
        ],
      );
}

class _SeverityPill extends StatelessWidget {
  const _SeverityPill({
    required this.count,
    required this.label,
    required this.color,
  });
  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withOpacity(0.4), width: 0.5),
        ),
        child: Text(
          '$count $label',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      );
}
