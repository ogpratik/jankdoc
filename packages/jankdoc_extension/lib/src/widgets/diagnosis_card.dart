import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:jankdoc_core/jankdoc_core.dart';

import 'confidence_badge.dart';

/// A single row in the diagnosis list.
///
/// Shows: severity dot · pattern ID · file:line (if attributed) · confidence
/// badge · recurrence count · timestamp.
class DiagnosisCard extends StatelessWidget {
  const DiagnosisCard({
    super.key,
    required this.diagnosis,
    required this.isSelected,
    required this.onTap,
  });

  final Diagnosis diagnosis;
  final bool isSelected;
  final VoidCallback onTap;

  static final _timeFormat = DateFormat('HH:mm:ss');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final severityColor = _severityColor(diagnosis.severity);

    final selectedBg = isDark
        ? const Color(0xFF2A2D2E)
        : const Color(0xFFE3F2FD);
    final hoverBg = isDark
        ? const Color(0xFF252526)
        : const Color(0xFFF0F4FF);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: isSelected ? selectedBg : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: hoverBg,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : severityColor,
                    width: isSelected ? 2 : 1,
                  ),
                  bottom: BorderSide(
                    color: isDark
                        ? const Color(0xFF2D2D2D)
                        : const Color(0xFFEEEEEE),
                    width: 0.5,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Row 1: severity + pattern ID + tier badge ─────────────
                  Row(
                    children: [
                      _SeverityDot(diagnosis.severity),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _humanisePattern(diagnosis.patternId),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _TierBadge(diagnosis.tier),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // ── Row 2: file:line + confidence + time ───────────────────
                  Row(
                    children: [
                      if (diagnosis.hasFileAttribution) ...[
                        Icon(
                          Icons.code,
                          size: 10,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            _shortPath(diagnosis.rootCause),
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurface.withOpacity(0.65),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ] else ...[
                        Flexible(
                          child: Text(
                            diagnosis.rootCause.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface.withOpacity(0.55),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ConfidenceBadge(diagnosis.confidence, compact: true),
                      if (diagnosis.recurrenceCount > 1) ...[
                        const SizedBox(width: 5),
                        _RecurrenceBadge(diagnosis.recurrenceCount),
                      ],
                      const Spacer(),
                      if (diagnosis.createdAt != null)
                        Text(
                          _timeFormat.format(diagnosis.createdAt!),
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurface.withOpacity(0.35),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _humanisePattern(String patternId) {
    // 'animated-builder-rebuild-storm' → 'Animated Builder Rebuild Storm'
    return patternId
        .split('-')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static String _shortPath(RootCause rc) {
    final file = rc.file ?? '';
    final parts = file.split('/');
    final name = parts.length > 2
        ? '…/${parts.skip(parts.length - 2).join('/')}'
        : file;
    return rc.line != null ? '$name:${rc.line}' : name;
  }

  static Color _severityColor(Severity s) => switch (s) {
        Severity.critical => const Color(0xFFE53935),
        Severity.high => const Color(0xFFFF6D00),
        Severity.medium => const Color(0xFFFFB300),
        Severity.low => const Color(0xFF42A5F5),
      };
}

// ── Internal helpers ──────────────────────────────────────────────────────────

class _SeverityDot extends StatelessWidget {
  const _SeverityDot(this.severity);
  final Severity severity;

  @override
  Widget build(BuildContext context) {
    final color = DiagnosisCard._severityColor(severity);
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge(this.tier);
  final DiagnosisTier tier;

  @override
  Widget build(BuildContext context) {
    final isRule = tier == DiagnosisTier.rule;
    final color = isRule
        ? const Color(0xFF66BB6A)
        : const Color(0xFF7E57C2);
    final label = isRule ? 'RULE' : 'LLM';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _RecurrenceBadge extends StatelessWidget {
  const _RecurrenceBadge(this.count);
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFEF9A9A).withOpacity(0.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.repeat, size: 9, color: Color(0xFFEF9A9A)),
          const SizedBox(width: 2),
          Text(
            '${count}x',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFFEF9A9A),
            ),
          ),
        ],
      ),
    );
  }
}
